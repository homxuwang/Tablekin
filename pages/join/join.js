const api = require('../../utils/api')
const cart = require('../../utils/cart')

Page({
  data: {
    code: '',
    codeInput: '',
    hasCode: false,
    needCode: false,
    nickname: '',
    joining: false,
    error: '',
    kitchenId: 0,
    kitchenName: '',
    joined: false,
  },

  onLoad(options) {
    const code = String((options && options.code) || '').trim()
    this.setData({
      code: code,
      hasCode: !!code,
      needCode: !code,
      nickname: cart.readDinerName(),
      error: '',
    })
  },

  onCodeInput(event) {
    const value = String(event.detail.value || '').trim()
    this.setData({ codeInput: value, hasCode: !!value })
  },

  onNicknameInput(event) {
    this.setData({ nickname: event.detail.value })
  },

  join() {
    const that = this
    if (this.data.joining || this.data.joined) return
    // 走链接进来时用链接里的码，手输的码作为补充
    const code = String(this.data.code || this.data.codeInput || '').trim()
    if (!code) {
      wx.showToast({ title: '请先填写邀请码', icon: 'none' })
      return
    }
    const nickname = String(this.data.nickname || '').trim()
    if (!nickname) {
      wx.showToast({ title: '请先填一下你的称呼', icon: 'none' })
      return
    }
    this.setData({ joining: true, error: '' })
    api
      .joinKitchenByCode(code, nickname)
      .then(function (kitchenId) {
        if (!kitchenId) throw new Error('加入失败，请让邀请你的人重新分享一次链接')
        cart.writeDinerName(nickname)
        return api.fetchKitchen(kitchenId).then(function (kitchen) {
          return { kitchenId: kitchenId, name: kitchen ? kitchen.name : '这个厨房' }
        })
      })
      .then(function (payload) {
        that.setData({
          joining: false,
          joined: true,
          kitchenId: payload.kitchenId,
          kitchenName: payload.name,
        })
        wx.showToast({ title: '已加入', icon: 'success' })
      })
      .catch(function (err) {
        that.setData({ joining: false, error: api.friendly(err) })
      })
  },

  goKitchen() {
    if (!this.data.kitchenId) return
    wx.redirectTo({ url: '/pages/menu/menu?kitchenId=' + this.data.kitchenId })
  },

  goManage() {
    if (!this.data.kitchenId) return
    wx.redirectTo({ url: '/pages/manage/manage?kitchenId=' + this.data.kitchenId })
  },

  goChef() {
    wx.switchTab({ url: '/pages/chef/chef' })
  },
})
