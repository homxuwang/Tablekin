const test = require('node:test')
const assert = require('node:assert/strict')
const { load } = require('./helpers.cjs')
const binaryFetch = require('../utils/binary-fetch.js')
// 直接引用小程序包内真正参与编译的那份产物（与 utils/cloud.js 同一份），
// 既保证测试覆盖真机运行的代码，也让测试不再依赖 npm install。
const { createMiniProgramWorkBuddyCloud } = require('../vendors/workbuddy-cloud-sdk.miniprogram')

const ENDPOINT = 'https://mp-api.app.workbuddy.host'
const KEY = 'wbpk_0123456789abcdef'

// 假 wx：只实现 SDK 真正会用到的 request 与 storage，并记录发出的字节。
function fakeWx(respond) {
  const seen = []
  const wx = {
    seen,
    request(options) {
      seen.push({
        url: options.url,
        method: options.method,
        header: options.header || {},
        bodyIsArrayBuffer: options.data instanceof ArrayBuffer,
        bodyLength: options.data && options.data.byteLength ? options.data.byteLength : 0,
        bodyType: typeof options.data,
        responseType: options.responseType,
      })
      const result = respond(options)
      setTimeout(() => {
        if (result && result.__fail) options.fail({ errMsg: result.__fail })
        else options.success(result)
      }, 0)
      return { abort() {} }
    },
    getStorageSync: () => null,
    setStorageSync() {},
    removeStorageSync() {},
  }
  return wx
}

function okJson(body) {
  return { statusCode: 200, header: { 'content-type': 'application/json' }, data: JSON.stringify(body) }
}

function buildCloud(wx) {
  return createMiniProgramWorkBuddyCloud({ endpoint: ENDPOINT, publishableKey: KEY, wx })
}

test('二进制上传保留SDK注入的项目凭证与每次最新的用户令牌', async () => {
  const wx = fakeWx(options => {
    const headers = Object.fromEntries(Object.entries(options.header).map(([k, v]) => [k.toLowerCase(), v]))
    if (headers['x-wb-webapp-access-key'] !== KEY || !headers.authorization) {
      return { statusCode: 401, data: { message: 'the client credential is invalid or revoked' } }
    }
    return okJson({ Id: 'i', Key: 'k' })
  })
  const cloud = buildCloud(wx)
  let token = 'test-session-one'
  cloud.auth.getAccessToken = async () => token
  binaryFetch.installBinaryUpload(cloud, wx)
  const first = await cloud.storage.upload('shared/chef/dishes/a.jpg', new ArrayBuffer(4), { contentType: 'image/jpeg' })
  assert.equal(first.error, null)
  token = 'test-session-two'
  const second = await cloud.storage.upload('shared/chef/dishes/b.jpg', new ArrayBuffer(4), { contentType: 'image/jpeg' })
  assert.equal(second.error, null)
  const headers = wx.seen.map(call => Object.fromEntries(Object.entries(call.header).map(([k, v]) => [k.toLowerCase(), v])))
  assert.equal(headers[0].authorization, 'Bearer test-session-one')
  assert.equal(headers[1].authorization, 'Bearer test-session-two')
  assert.equal(headers[1]['x-wb-webapp-access-key'], KEY)
})

test('根因：不装补丁时，SDK 直接拒绝二进制 body（这就是「1 张未上传」的来源）', async () => {
  const wx = fakeWx(() => okJson({ Id: 'i', Key: 'k' }))
  const cloud = buildCloud(wx)
  const result = await cloud.storage.upload('shared/chef/dishes/a.jpg', new ArrayBuffer(8), {
    contentType: 'image/jpeg',
  })
  assert.equal(result.data, null)
  assert.match(result.error.message, /暂不支持非字符串/)
  assert.equal(wx.seen.length, 0, '请求根本没发出去')
})

test('装上补丁后，图片字节原样交给 wx.request，不再被拦下', async () => {
  const wx = fakeWx(() => okJson({ Id: 'i', Key: 'runtime/shared/chef/dishes/a.jpg' }))
  const cloud = buildCloud(wx)
  assert.equal(binaryFetch.installBinaryUpload(cloud, wx), true)

  const bytes = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3])
  const result = await cloud.storage.upload('shared/chef/dishes/a.jpg', bytes.buffer, {
    contentType: 'image/jpeg',
  })

  assert.equal(result.error, null)
  assert.equal(result.data.path, 'shared/chef/dishes/a.jpg')
  assert.equal(wx.seen.length, 1)
  const sent = wx.seen[0]
  assert.equal(sent.bodyIsArrayBuffer, true, '必须是原始字节而不是字符串')
  assert.equal(sent.bodyLength, 11)
  assert.equal(sent.method, 'POST')
  assert.equal(sent.header['content-type'], 'image/jpeg', 'content-type 决定微信是否做字符串转换')
  assert.match(sent.url, /\/object\//)
  assert.equal(sent.responseType, 'text')
})

test('Uint8Array 也会还原成底层 ArrayBuffer', async () => {
  const wx = fakeWx(() => okJson({ Id: 'i', Key: 'k' }))
  const cloud = buildCloud(wx)
  binaryFetch.installBinaryUpload(cloud, wx)
  await cloud.storage.upload('shared/chef/dishes/b.jpg', new Uint8Array([1, 2, 3, 4]), {
    contentType: 'image/jpeg',
  })
  assert.equal(wx.seen[0].bodyIsArrayBuffer, true)
  assert.equal(wx.seen[0].bodyLength, 4)
})

test('只有二进制走自定义通道，字符串 body 仍交给 SDK 自己的实现', async () => {
  const wx = fakeWx(options => {
    if (String(options.url).includes('/object/sign/')) {
      return okJson([{ signedUrl: 'https://x/y?token=t', path: 'shared/chef/dishes/a.jpg' }])
    }
    return okJson({ Id: 'i', Key: 'k' })
  })
  const cloud = buildCloud(wx)
  binaryFetch.installBinaryUpload(cloud, wx)

  const signed = await cloud.storage.createSignedUrls(['shared/chef/dishes/a.jpg'], 3600)
  assert.equal(signed.error, null)
  assert.equal(wx.seen.length, 1)
  assert.equal(wx.seen[0].bodyType, 'string', '签名请求是 JSON 文本，不该走二进制通道')
})

test('服务端报错时，错误能被 SDK 正常解析出来', async () => {
  const wx = fakeWx(() => ({
    statusCode: 400,
    header: { 'content-type': 'application/json' },
    data: JSON.stringify({ statusCode: '400', error: 'bad_request', message: '图片格式不支持' }),
  }))
  const cloud = buildCloud(wx)
  binaryFetch.installBinaryUpload(cloud, wx)
  const result = await cloud.storage.upload('shared/chef/dishes/c.jpg', new ArrayBuffer(4), {
    contentType: 'image/jpeg',
  })
  assert.equal(result.data, null)
  assert.match(String(result.error && result.error.message), /图片格式不支持|400/)
})

test('网络失败时抛出带 wx 信息的错误，前端能翻成人话', async () => {
  const wx = fakeWx(() => ({ __fail: 'request:fail socket timeout' }))
  const cloud = buildCloud(wx)
  binaryFetch.installBinaryUpload(cloud, wx)
  const result = await cloud.storage.upload('shared/chef/dishes/d.jpg', new ArrayBuffer(4), {
    contentType: 'image/jpeg',
  })
  assert.equal(result.data, null)
  assert.match(String(result.error && result.error.message), /wx\.request failed/)
})

test('isBinaryBody 只认二进制，字符串一律交回 SDK', () => {
  assert.equal(binaryFetch.isBinaryBody(new ArrayBuffer(2)), true)
  assert.equal(binaryFetch.isBinaryBody(new Uint8Array(2)), true)
  assert.equal(binaryFetch.isBinaryBody('{"a":1}'), false)
  assert.equal(binaryFetch.isBinaryBody(null), false)
})

test('Headers 实例 / 数组 / 普通对象都能摊平', () => {
  assert.deepEqual(binaryFetch.toPlainHeaders({ a: '1' }), { a: '1' })
  assert.deepEqual(binaryFetch.toPlainHeaders([['a', '1']]), { a: '1' })
  const headers = new Headers({ 'x-upsert': 'true' })
  assert.equal(binaryFetch.toPlainHeaders(headers)['x-upsert'], 'true')
})

test('响应体无论是字符串还是已解析对象，都还原成文本给 SDK', async () => {
  const obj = await binaryFetch.toResponse({
    statusCode: 200,
    header: {},
    data: { Id: 'i', Key: 'k' },
  }).json()
  assert.deepEqual(obj, { Id: 'i', Key: 'k' })
  const res = binaryFetch.toResponse({ statusCode: 500, header: { 'Content-Type': 'text/plain' }, data: 'boom' })
  assert.equal(res.ok, false)
  assert.equal(await res.text(), 'boom')
})

// ---------- api 层 ----------

function uploadHarness(options = {}) {
  const calls = []
  const files = options.files || {}
  const cloud = {
    auth: { getSession: async () => ({ data: { user: { id: 'chef' } } }) },
    database: { rpc: async () => ({ data: {} }) },
    storage: {
      sharedPath: (uid, p) => 'shared/' + uid + '/' + p,
      upload: async (path, body, opts) => {
        calls.push({ path, body, opts })
        return (
          options.uploadResult || { data: { path, id: 'i1', fullPath: path }, error: null }
        )
      },
    },
  }
  const wx = {
    getFileSystemManager: () => ({
      readFileSync: p => {
        if (!(p in files)) throw new Error('readFileSync:fail no such file')
        return files[p]
      },
    }),
  }
  const api = load('utils/api.js', { './cloud': { cloud } }, { wx })
  return { api, calls, cloud, wx }
}

test('上传菜品图片：读到的字节原样交给 SDK，落库路径是 shared/<uid>/dishes/…', async () => {
  const { api, calls } = uploadHarness({ files: { 'tmp://a.jpg': new ArrayBuffer(2048) } })
  const path = await api.uploadDishImage('tmp://a.jpg')
  assert.match(path, /^shared\/chef\/dishes\/\d+-\d+\.jpg$/)
  assert.equal(calls.length, 1)
  assert.equal(calls[0].opts.contentType, 'image/jpeg')
  assert.equal(calls[0].body.byteLength, 2048)
})

test('空文件与超大图在发出请求前就被拦下', async () => {
  const empty = uploadHarness({ files: { 'tmp://e.jpg': new ArrayBuffer(0) } })
  await assert.rejects(() => empty.api.uploadDishImage('tmp://e.jpg'), /image_empty/)
  assert.equal(empty.calls.length, 0, '不该白跑一趟网络')

  const big = uploadHarness({ files: { 'tmp://b.jpg': new ArrayBuffer(11 * 1024 * 1024) } })
  await assert.rejects(() => big.api.uploadDishImage('tmp://b.jpg'), /image_too_large/)
  assert.equal(big.calls.length, 0)
})

test('上传失败时保留 SDK 的错误名，前端文案能讲清楚', async () => {
  const { api } = uploadHarness({
    files: { 'tmp://a.jpg': new ArrayBuffer(16) },
    uploadResult: { data: null, error: { name: 'StorageUnknownError', message: 'wx.request failed: request:fail' } },
  })
  let caught = null
  try {
    await api.uploadDishImage('tmp://a.jpg')
  } catch (err) {
    caught = err
  }
  assert.ok(caught)
  assert.match(api.friendly(caught), /网络/)
})

test('三种典型失败都有人话提示', () => {
  const { api } = uploadHarness()
  assert.match(api.friendly(new Error('image_empty')), /换一张/)
  assert.match(api.friendly(new Error('image_too_large')), /10MB/)
  assert.match(api.friendly(new Error('createMiniProgramFetch: 暂不支持非字符串 body')), /上传通道/)
  assert.match(api.friendly({ message: 'wx.request failed: request:fail timeout' }), /超时/)
})
