/**
 * 小程序 SDK 的 fetch 适配层只接受字符串 body：
 *   createMiniProgramFetch: 暂不支持非字符串 body（ArrayBuffer/FormData 待补）。
 * 于是 cloud.storage.upload() 一传 ArrayBuffer 就抛错，菜品图片永远传不上去。
 *
 * 这里只接管「请求体是二进制」这一条路径，用 wx.request 把 ArrayBuffer 原样发出去。
 * 微信文档写明 data 支持 ArrayBuffer，且只对两种 content-type 做字符串转换
 * （application/json 与 x-www-form-urlencoded），图片类型会按原始字节发送。
 *
 * 其余请求（登录、数据库、签名 URL）与流式响应仍走 SDK 自己的实现，不重复造轮子。
 */

var BINARY_UPLOAD_TIMEOUT = 60000

function isBinaryBody(body) {
  if (!body || typeof body === 'string') return false
  if (typeof ArrayBuffer !== 'undefined' && body instanceof ArrayBuffer) return true
  if (typeof Uint8Array !== 'undefined' && body instanceof Uint8Array) return true
  return false
}

// Uint8Array 要还原成它底层的 buffer，否则 wx.request 拿到的是视图而不是字节。
function toArrayBuffer(body) {
  if (typeof Uint8Array !== 'undefined' && body instanceof Uint8Array) {
    return body.byteOffset === 0 && body.byteLength === body.buffer.byteLength
      ? body.buffer
      : body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength)
  }
  return body
}

// SDK 传进来的 headers 可能是 Headers 实例、数组或普通对象。
function toPlainHeaders(headers) {
  if (!headers) return {}
  if (typeof headers.get === 'function' && typeof headers.forEach === 'function') {
    var out = {}
    headers.forEach(function (value, key) {
      out[key] = value
    })
    return out
  }
  if (Array.isArray(headers)) {
    var map = {}
    headers.forEach(function (pair) {
      if (Array.isArray(pair)) map[pair[0]] = pair[1]
    })
    return map
  }
  return Object.assign({}, headers)
}

function makeHeaders(raw) {
  if (typeof Headers === 'function') {
    try {
      return new Headers(raw || {})
    } catch (err) {
      /* 小程序里 Headers 可能只是占位实现，退回下面的简易对象 */
    }
  }
  var lower = {}
  Object.keys(raw || {}).forEach(function (key) {
    lower[String(key).toLowerCase()] = raw[key]
  })
  return {
    get: function (name) {
      return lower[String(name).toLowerCase()] || null
    },
    has: function (name) {
      return Object.prototype.hasOwnProperty.call(lower, String(name).toLowerCase())
    },
  }
}

// wx.request 可能把 JSON 响应当成对象返回（dataType 默认 json），统一成文本，
// 让 SDK 按原样解析。
function toText(data) {
  if (typeof data === 'string') return data
  if (data === null || data === undefined) return ''
  if (typeof data === 'object') {
    try {
      return JSON.stringify(data)
    } catch (err) {
      return ''
    }
  }
  return String(data)
}

function toResponse(result) {
  var status = (result && result.statusCode) || 0
  var text = toText(result && result.data)
  return {
    status: status,
    ok: status >= 200 && status < 300,
    statusText: '',
    headers: makeHeaders(result && result.header),
    body: null,
    text: function () {
      return Promise.resolve(text)
    },
    json: function () {
      return Promise.resolve().then(function () {
        return JSON.parse(text || '{}')
      })
    },
  }
}

function sendBinary(wxInstance, url, method, headers, body, signal) {
  return new Promise(function (resolve, reject) {
    if (signal && signal.aborted) {
      var aborted = new Error('The operation was aborted.')
      aborted.name = 'AbortError'
      reject(aborted)
      return
    }
    var task = wxInstance.request({
      url: url,
      method: method,
      header: headers,
      data: body,
      responseType: 'text',
      timeout: BINARY_UPLOAD_TIMEOUT,
      success: function (result) {
        resolve(toResponse(result))
      },
      fail: function (result) {
        reject(new Error('wx.request failed: ' + ((result && result.errMsg) || 'unknown')))
      },
    })
    if (signal && task && typeof task.abort === 'function') {
      signal.addEventListener('abort', function () {
        task.abort()
        var err = new Error('The operation was aborted.')
        err.name = 'AbortError'
        reject(err)
      })
    }
  })
}

/**
 * SDK config 是冻结对象，无法在初始化后替换最底层传输。
 * 因此只接管存储二进制分支，并遵循 createCloudFetch 的认证规则：
 * 每次取当前令牌（SDK 会续期），附加项目凭证，保留显式 Authorization。
 * 非二进制请求继续走 SDK 原认证和传输。
 * @returns {boolean} 是否成功挂上；失败时调用方应给出明确提示而不是静默。
 */
function installBinaryUpload(cloud, wxInstance) {
  var config = cloud && cloud.config
  var fileApi = cloud && cloud.storage && cloud.storage.fileApi
  if (!fileApi || typeof fileApi.fetch !== 'function' || !config || !config.publishableKey || !cloud.auth || typeof cloud.auth.getAccessToken !== 'function') return false
  if (fileApi.fetch.__binaryUploadInstalled) return true

  var baseFetch = fileApi.fetch
  var patched = async function (input, init) {
    var body = init && init.body
    if (!isBinaryBody(body)) return baseFetch(input, init)
    var headers = toPlainHeaders(init && init.headers)
    // 大小写不敏感，避免同名凭证头重复。
    Object.keys(headers).forEach(function (name) {
      if (name.toLowerCase() === 'x-wb-webapp-access-key') delete headers[name]
    })
    headers['x-wb-webapp-access-key'] = config.publishableKey
    var hasAuthorization = Object.keys(headers).some(function (name) { return name.toLowerCase() === 'authorization' })
    if (!hasAuthorization) {
      var token = await cloud.auth.getAccessToken()
      if (token) headers.Authorization = 'Bearer ' + token
    }
    return sendBinary(
      wxInstance,
      String(input),
      ((init && init.method) || 'POST').toUpperCase(),
      headers,
      toArrayBuffer(body),
      init && init.signal
    )
  }
  patched.__binaryUploadInstalled = true
  fileApi.fetch = patched
  return true
}

module.exports = { installBinaryUpload, isBinaryBody, toPlainHeaders, toResponse }
