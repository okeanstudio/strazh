import { HeadObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { Upload } from '@aws-sdk/lib-storage';
import { createClient } from '@supabase/supabase-js';
import { createHmac } from 'node:crypto';
import { Readable } from 'node:stream';

function requiredEnv(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const supabaseUrl = requiredEnv('SUPABASE_URL').replace(/\/+$/, '');
const supabaseServiceRoleKey = requiredEnv('SUPABASE_SERVICE_ROLE_KEY');
const s3Endpoint = requiredEnv('S3_ENDPOINT');
const s3Region = requiredEnv('S3_REGION');
const s3Bucket = requiredEnv('S3_BUCKET');
const s3AccessKeyId = requiredEnv('S3_ACCESS_KEY_ID');
const s3SecretAccessKey = requiredEnv('S3_SECRET_ACCESS_KEY');
const publicUrlSecret = requiredEnv('S3_PUBLIC_URL_SECRET');
const publicUrlBase =
  process.env.S3_PUBLIC_URL_BASE?.trim() ||
  'https://api.strazh.chat/s3_public_asset.php';
const publicAssetBuckets = new Set([
  'avatars',
  'channel_avatars',
  'group_avatars',
  'chat_wallpapers',
]);
if (new URL(s3Endpoint).protocol !== 'https:') {
  throw new Error('S3_ENDPOINT must use HTTPS');
}

const supabase = createClient(supabaseUrl, supabaseServiceRoleKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

const s3 = new S3Client({
  endpoint: s3Endpoint,
  region: s3Region,
  forcePathStyle: true,
  credentials: {
    accessKeyId: s3AccessKeyId,
    secretAccessKey: s3SecretAccessKey,
  },
});

const pageSize = 100;

async function* listObjects(bucketId, prefix = '') {
  let offset = 0;
  while (true) {
    const { data, error } = await supabase.storage.from(bucketId).list(prefix, {
      limit: pageSize,
      offset,
      sortBy: { column: 'name', order: 'asc' },
    });
    if (error) {
      throw new Error(`Could not list ${bucketId}/${prefix}: ${error.message}`);
    }
    if (!data) {
      throw new Error(`Storage returned no object list for ${bucketId}/${prefix}`);
    }

    for (const entry of data) {
      const objectPath = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.id == null) {
        yield* listObjects(bucketId, objectPath);
      } else {
        yield objectPath;
      }
    }

    if (data.length < pageSize) return;
    offset += data.length;
  }
}

function encodeObjectPath(bucketId, objectPath) {
  return [bucketId, ...objectPath.split('/')]
    .map((segment) => encodeURIComponent(segment))
    .join('/');
}

async function migrateObject(bucketId, objectPath) {
  const sourceUrl = `${supabaseUrl}/storage/v1/object/${encodeObjectPath(bucketId, objectPath)}`;
  const response = await fetch(sourceUrl, {
    headers: {
      apikey: supabaseServiceRoleKey,
      Authorization: `Bearer ${supabaseServiceRoleKey}`,
    },
  });
  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(
      `Could not download ${bucketId}/${objectPath} (${response.status}): ${errorBody}`,
    );
  }
  if (!response.body) {
    throw new Error(`No response body for ${bucketId}/${objectPath}`);
  }

  const key = `${bucketId}/${objectPath}`;
  const contentLengthHeader = response.headers.get('content-length');
  const contentLength =
    contentLengthHeader == null ? undefined : Number(contentLengthHeader);
  if (
    contentLength !== undefined &&
    (!Number.isSafeInteger(contentLength) || contentLength < 0)
  ) {
    throw new Error(`Invalid content length for ${bucketId}/${objectPath}`);
  }

  const transfer = new Upload({
    client: s3,
    params: {
      Bucket: s3Bucket,
      Key: key,
      Body: Readable.fromWeb(response.body),
      ...(contentLength === undefined ? {} : { ContentLength: contentLength }),
      ...(response.headers.get('content-type')
        ? { ContentType: response.headers.get('content-type') }
        : {}),
      ...(response.headers.get('cache-control')
        ? { CacheControl: response.headers.get('cache-control') }
        : {}),
    },
    partSize: 8 * 1024 * 1024,
    queueSize: 2,
    leavePartsOnError: false,
  });

  await transfer.done();

  const uploaded = await s3.send(
    new HeadObjectCommand({ Bucket: s3Bucket, Key: key }),
  );
  if (
    contentLength !== undefined &&
    uploaded.ContentLength !== contentLength
  ) {
    throw new Error(
      `Size verification failed for ${bucketId}/${objectPath}: expected ${contentLength}, got ${uploaded.ContentLength}`,
    );
  }
}

function getStorageObject(value, allowedBuckets) {
  if (typeof value !== 'string' || value.length === 0) return null;

  let url;
  try {
    url = new URL(value);
  } catch {
    return null;
  }

  const segments = url.pathname.split('/').filter(Boolean).map(decodeURIComponent);
  const objectIndex = segments.indexOf('object');
  if (objectIndex === -1) return null;

  let bucketIndex = objectIndex + 1;
  if (['public', 'private', 'sign'].includes(segments[bucketIndex])) {
    bucketIndex++;
  }
  const bucket = segments[bucketIndex];
  const path = segments.slice(bucketIndex + 1).join('/');
  if (!allowedBuckets.has(bucket) || path.length === 0) return null;
  return { bucket, path };
}

function createPublicAssetUrl(bucket, path) {
  const signature = createHmac('sha256', publicUrlSecret)
    .update(`${bucket}\n${path}`)
    .digest('hex');
  const query = new URLSearchParams({ bucket, path, signature });
  return `${publicUrlBase}?${query.toString()}`;
}

function replacePublicStorageUrl(value) {
  const object = getStorageObject(value, publicAssetBuckets);
  return object ? createPublicAssetUrl(object.bucket, object.path) : value;
}

function replaceStorageUrlWithPath(value, allowedBuckets) {
  const object = getStorageObject(value, allowedBuckets);
  return object?.path ?? value;
}

async function updateAvatarUrls(table, idColumn, urlColumn) {
  let lastId = '';
  let updated = 0;
  while (true) {
    let query = supabase
      .from(table)
      .select(`${idColumn},${urlColumn}`)
      .not(urlColumn, 'is', null)
      .order(idColumn, { ascending: true })
      .limit(pageSize);
    if (lastId) query = query.gt(idColumn, lastId);

    const { data, error } = await query;
    if (error) {
      throw new Error(`Could not read ${table}.${urlColumn}: ${error.message}`);
    }
    if (!data) {
      throw new Error(`Supabase returned no rows for ${table}.${urlColumn}`);
    }
    if (data.length === 0) return updated;

    for (const row of data) {
      lastId = String(row[idColumn]);
      const newUrl = replacePublicStorageUrl(row[urlColumn]);
      if (newUrl === row[urlColumn]) continue;

      const { error: updateError } = await supabase
        .from(table)
        .update({ [urlColumn]: newUrl })
        .eq(idColumn, row[idColumn]);
      if (updateError) {
        throw new Error(
          `Could not update ${table}.${urlColumn} for ${lastId}: ${updateError.message}`,
        );
      }
      updated++;
    }

    if (data.length < pageSize) return updated;
  }
}

async function updateStoragePathUrls(table, idColumn, urlColumn, buckets) {
  let lastId = '';
  let updated = 0;
  while (true) {
    let query = supabase
      .from(table)
      .select(`${idColumn},${urlColumn}`)
      .not(urlColumn, 'is', null)
      .order(idColumn, { ascending: true })
      .limit(pageSize);
    if (lastId) query = query.gt(idColumn, lastId);

    const { data, error } = await query;
    if (error) {
      throw new Error(`Could not read ${table}.${urlColumn}: ${error.message}`);
    }
    if (!data) {
      throw new Error(`Supabase returned no rows for ${table}.${urlColumn}`);
    }
    if (data.length === 0) return updated;

    for (const row of data) {
      lastId = String(row[idColumn]);
      const newPath = replaceStorageUrlWithPath(row[urlColumn], buckets);
      if (newPath === row[urlColumn]) continue;

      const { error: updateError } = await supabase
        .from(table)
        .update({ [urlColumn]: newPath })
        .eq(idColumn, row[idColumn]);
      if (updateError) {
        throw new Error(
          `Could not update ${table}.${urlColumn} for ${lastId}: ${updateError.message}`,
        );
      }
      updated++;
    }

    if (data.length < pageSize) return updated;
  }
}

async function updateMessageStoragePaths() {
  let lastId = '';
  let updated = 0;
  while (true) {
    let query = supabase
      .from('messages')
      .select('id,encrypted_content,file_url,voice_url')
      .order('id', { ascending: true })
      .limit(pageSize);
    if (lastId) query = query.gt('id', lastId);

    const { data, error } = await query;
    if (error) throw new Error(`Could not read messages: ${error.message}`);
    if (!data) throw new Error('Supabase returned no messages');
    if (data.length === 0) return updated;

    for (const row of data) {
      lastId = String(row.id);
      const changes = {};
      for (const column of ['encrypted_content', 'file_url', 'voice_url']) {
        const buckets =
          column === 'voice_url'
            ? new Set(['voice_messages'])
            : column === 'file_url'
              ? new Set(['chat_files', 'chat_media'])
              : new Set(['chat_media']);
        const newPath = replaceStorageUrlWithPath(row[column], buckets);
        if (newPath !== row[column]) changes[column] = newPath;
      }
      if (Object.keys(changes).length === 0) continue;

      const { error: updateError } = await supabase
        .from('messages')
        .update(changes)
        .eq('id', row.id);
      if (updateError) {
        throw new Error(`Could not update message ${lastId}: ${updateError.message}`);
      }
      updated++;
    }

    if (data.length < pageSize) return updated;
  }
}

async function updateUserAvatarUrls() {
  let page = 1;
  let updated = 0;
  while (true) {
    const { data, error } = await supabase.auth.admin.listUsers({
      page,
      perPage: pageSize,
    });
    if (error) {
      throw new Error(`Could not list users: ${error.message}`);
    }
    if (!data) throw new Error('Supabase returned no users');

    for (const user of data.users) {
      const metadata = user.user_metadata ?? {};
      const newUrl = replacePublicStorageUrl(metadata.avatar_url);
      if (newUrl === metadata.avatar_url) continue;

      const { error: updateError } = await supabase.auth.admin.updateUserById(
        user.id,
        { user_metadata: { ...metadata, avatar_url: newUrl } },
      );
      if (updateError) {
        throw new Error(`Could not update avatar for ${user.id}: ${updateError.message}`);
      }
      updated++;
    }

    if (data.users.length < pageSize) return updated;
    page++;
  }
}

async function rewritePublicAssetUrls() {
  const updates = [
    ['rooms', 'id', 'avatar_url'],
    ['stories', 'id', 'author_avatar_url'],
    ['messages', 'id', 'sender_avatar'],
  ];
  let total = await updateUserAvatarUrls();
  for (const [table, idColumn, urlColumn] of updates) {
    total += await updateAvatarUrls(table, idColumn, urlColumn);
  }
  total += await updateStoragePathUrls(
    'stories',
    'id',
    'image_url',
    new Set(['stories']),
  );
  total += await updateMessageStoragePaths();
  return total;
}

async function main() {
  const { data: buckets, error } = await supabase.storage.listBuckets();
  if (error) {
    throw new Error(`Could not list Storage buckets: ${error.message}`);
  }
  if (!buckets) {
    throw new Error('Storage returned no bucket list');
  }
  if (buckets.length === 0) {
    console.log('No Storage buckets found.');
    return;
  }

  let total = 0;
  for (const bucket of buckets) {
    let bucketCount = 0;
    for await (const objectPath of listObjects(bucket.id)) {
      await migrateObject(bucket.id, objectPath);
      bucketCount++;
      if (bucketCount % 100 === 0) {
        console.log(`Copied ${bucketCount} objects from ${bucket.id}`);
      }
    }
    total += bucketCount;
    console.log(`Copied ${bucketCount} objects from ${bucket.id}`);
  }

  const updatedAssetUrls = await rewritePublicAssetUrls();
  console.log(
    `Migration complete: ${total} objects copied; ${updatedAssetUrls} public asset URLs updated.`,
  );
}

main().catch((error) => {
  console.error(
    'Storage migration failed:',
    error instanceof Error ? error.message : error,
  );
  process.exitCode = 1;
});
