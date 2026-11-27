// 用相对路径引用，而不是包名 '@tencent-ai/workbuddy-cloud-sdk/miniprogram'：
// SDK 是零依赖单文件，直接内置在 vendors/ 下。这样既不依赖 npm 解析、
// 也不受「构建 npm」影响（构建会按 package.json 重建 miniprogram_npm，可能把手工产物清掉），
// 发布校验因此不需要跑 npm install。
const { createMiniProgramWorkBuddyCloud } = require('../vendors/workbuddy-cloud-sdk.miniprogram')
const { createDiagnosticWx } = require('./workbuddy-cloud-diagnostics')
const { installBinaryUpload } = require('./binary-fetch')
const publicConfig = require('./cloud-config')

// 全局只初始化一次，数据库 / 登录 / 存储共用这一个客户端。
const wxClient = createDiagnosticWx(wx)

const cloud = createMiniProgramWorkBuddyCloud({
  endpoint: publicConfig.endpoint,
  publishableKey: publicConfig.publishableKey,
  wx: wxClient,
})

// SDK 的 fetch 适配层拒绝二进制 body，不装这一层的话菜品图片一张都传不上去。
if (!installBinaryUpload(cloud, wxClient)) {
  console.error('[WorkBuddy Cloud] binary upload not installed; image upload will fail')
}

module.exports = { cloud, publicConfig }
