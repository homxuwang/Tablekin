const api = require('./utils/api')

App({
  globalData: {
    ready: null,
    user: null,
    // 跨页跳转的小提示：比如「下厨」页点待处理，订单页据此停在「我收到的」那一栏
    ordersSegment: '',
  },

  onLaunch() {
    // 进入小程序即静默取得微信身份，页面直接可读写自己的数据。
    this.globalData.ready = api
      .ensureSession()
      .then((user) => {
        this.globalData.user = user
        return user
      })
      .catch((err) => {
        console.error(
          '[吃好喝好] 登录失败',
          JSON.stringify({ stage: 'app-onLaunch', message: (err && err.message) || 'unknown' })
        )
        return null
      })
  },
})
