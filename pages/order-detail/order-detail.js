const api = require('../../utils/api')
const cart = require('../../utils/cart')
const refresh = require('../../utils/live-refresh')
const haptics = require('../../utils/haptics')

function pad(n) {
  return n < 10 ? '0' + n : String(n)
}

function stamp(value) {
  if (!value) return ''
  const date = new Date(value)
  if (isNaN(date.getTime())) return ''
  const week = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']
  return (
    date.getMonth() +
    1 +
    '月' +
    date.getDate() +
    '日 ' +
    week[date.getDay()] +
    ' ' +
    pad(date.getHours()) +
    ':' +
    pad(date.getMinutes())
  )
}

// 一单的详情页：顾客看进度，大厨在这儿回话、接单、出餐。
Page({
  data: {
    loading: true,
    error: '',
    order: null,
    items: [],
    kitchen: null,
    kitchenId: 0,
    kitchenName: '',
    steps: [],
    statusText: '',
    statusTone: 'wait',
    statusHint: '',
    isChef: false,
    isMine: false,
    createdAtText: '',
    mealTimeText: '',
    total: 0,
    busy: false,
  },

  onLoad(options) {
    this.orderId = Number((options && options.id) || 0)
    if (!this.orderId) {
      this.setData({ loading: false, error: '没有指定订单，请从订单列表进入' })
      return
    }
  },

  onShow() {
    if (!this.orderId) return
    refresh.start(this, () => this.load({ silent: true }))
    this.load()
  },
  onHide() { refresh.stop(this) },
  onUnload() { refresh.stop(this) },
  onPullDownRefresh() {
    return this.load().then(() => wx.stopPullDownRefresh())
  },

  onShareAppMessage() {
    const name = this.data.kitchenName || '这家厨房'
    return {
      title: name + ' 的菜单，来点几道',
      path: this.data.kitchenId ? '/pages/menu/menu?kitchenId=' + this.data.kitchenId : '/pages/home/home',
    }
  },

  load(options) {
    if (this._refreshVisible === false) return Promise.resolve()
    const silent = options && options.silent
    const epoch = this._refreshEpoch || 0
    if (this._detailRequest && !silent) return this._detailRequest.then(() => {
      if (epoch === (this._refreshEpoch || 0)) return this.load(options)
    })
    return refresh.singleFlight(this, '_detailRequest', () => this.loadDetail(!!silent))
  },

  loadDetail(silent) {
    const that = this
    if (!silent) this.setData({ loading: true, error: '' })
    return api
      .requireUser()
      .then(function (user) {
        that.userId = user.id
        return api.fetchOrder(that.orderId)
      })
      .then(function (order) {
        if (!order) throw new Error('这一单不存在，或者你看不到它')
        that.order = order
        return Promise.all([
          api.fetchOrderItems([order.id]),
          api.fetchKitchen(order.kitchen_id).catch(function () {
            return null
          }),
          api.fetchMembers(order.kitchen_id).catch(function () {
            return []
          }),
        ]).then(function (result) {
          return { order: order, items: result[0] || [], kitchen: result[1], members: result[2] || [] }
        })
      })
      .then(function (payload) {
        const order = payload.order
        const status = api.orderStatus(order)
        const isChef = payload.members.some(function (row) {
          return row.user_id === that.userId
        })
        const total = payload.items.reduce(function (sum, row) {
          return sum + Number(row.quantity || 0)
        }, 0)
        const name = payload.kitchen ? payload.kitchen.name : ''
        let hint = ''
        if (order.status === 'cancelled') hint = '点菜人已撤回这一单，大厨无需再做'
        else if (order.status === 'rejected') hint = order.reject_reason || '大厨回复这单暂时做不了'
        else if (order.status === 'done') hint = '做好了，吃饭吧'
        else if (order.status === 'accepted') hint = '大厨接了这一单，正在做'
        else if (order.acked_at) hint = '大厨看到这一单了'
        else hint = '已经发给大厨，等 TA 回话'
        that.setData({
          loading: false,
          error: '',
          order: order,
          items: payload.items,
          kitchen: payload.kitchen,
          kitchenId: order.kitchen_id || 0,
          kitchenName: name,
          steps: api.orderSteps(order).map(function (step) {
            return Object.assign({}, step, { atText: stamp(step.at) })
          }),
          statusText: status.text,
          statusTone: status.tone,
          statusHint: hint,
          isChef: isChef,
          isMine: order.diner_id === that.userId,
          createdAtText: stamp(order.created_at),
          mealTimeText: api.mealScheduleText(order),
          total: total,
        })
        wx.setNavigationBarTitle({ title: name ? name + ' · 订单' : '订单详情' })
      })
      .catch(function (err) {
        that.setData({ loading: false, error: api.friendly(err) })
      })
  },

  buildSummary() {
    const order = this.data.order
    if (!order) return ''
    const lines = []
    lines.push('给「' + (this.data.kitchenName || '厨房') + '」的点菜（' + this.data.items.length + ' 道）')
    if (order.diner_name) lines.push('点菜人：' + order.diner_name)
    lines.push('想吃时间：' + this.data.mealTimeText)
    lines.push('')
    this.data.items.forEach(function (item, index) {
      lines.push(index + 1 + '. ' + item.dish_name + ' ×' + item.quantity)
    })
    if (order.note) {
      lines.push('')
      lines.push('备注：' + order.note)
    }
    return lines.join('\n')
  },

  copySummary() {
    const text = this.buildSummary()
    if (!text) return
    wx.setClipboardData({
      data: text,
      success() {
        wx.showToast({ title: '清单已复制', icon: 'success' })
      },
    })
  },

  ack() {
    const that = this
    if (this.data.busy) return
    this.setData({ busy: true })
    api
      .ackOrder(this.orderId)
      .then(function () {
        that.setData({ busy: false })
        wx.showToast({ title: '已回复收到', icon: 'success' })
        that.load()
      })
      .catch(function (err) {
        that.setData({ busy: false })
        wx.showModal({ title: '回复失败', content: api.friendly(err), showCancel: false })
      })
  },

  accept() {
    const that = this
    if (this.data.busy) return
    this.setData({ busy: true })
    api
      .acceptOrder(this.orderId)
      .then(function (result) {
        that.setData({ busy: false })
        if (result.ok) {
          wx.showToast({ title: '已接单，库存已扣', icon: 'success' })
          that.load()
          return
        }
        const lines = result.problems.map(function (item) {
          return (
            '· ' +
            item.ingredientName +
            '：需 ' +
            api.round1(item.needed) +
            item.unit +
            '，只剩 ' +
            api.round1(item.stock) +
            item.unit
          )
        })
        wx.showModal({
          title: '食材不够，没法接单',
          content: lines.join('\n') + '\n\n补货后可以再点一次「接单」。',
          showCancel: false,
          confirmText: '知道了',
        })
      })
      .catch(function (err) {
        that.setData({ busy: false })
        wx.showModal({ title: '接单失败', content: api.friendly(err), showCancel: false })
      })
  },

  finish() {
    const that = this
    if (this.data.busy) return
    this.setData({ busy: true })
    api
      .finishOrder(this.orderId)
      .then(function () {
        that.setData({ busy: false })
        wx.showToast({ title: '已标记出餐', icon: 'success' })
        that.load()
      })
      .catch(function (err) {
        that.setData({ busy: false })
        wx.showModal({ title: '操作失败', content: api.friendly(err), showCancel: false })
      })
  },

  reject() {
    const that = this
    if (this.data.busy) return
    this.setData({ busy: true })
    wx.showModal({
      title: '这单做不了？',
      editable: true,
      placeholderText: '原因（可不填），会显示给点菜的人',
      success(res) {
        if (!res.confirm) { that.setData({ busy: false }); return }
        api
          .rejectOrder(that.orderId, res.content)
          .then(function () {
            that.setData({ busy: false })
            wx.showToast({ title: '已回复', icon: 'success' })
            that.load()
          })
          .catch(function (err) {
            that.setData({ busy: false })
            wx.showModal({ title: '操作失败', content: api.friendly(err), showCancel: false })
          })
      },
      fail() { that.setData({ busy: false }) },
    })
  },

  cancel() {
    const that = this
    if (this.data.busy) return
    this.setData({ busy: true })
    wx.showModal({
      title: '撤回这一单？',
      content: '大厨那边会看到这单已撤回，不用再做了。已经接单的单撤不了，那时候得跟大厨说一声。',
      confirmColor: '#D64545',
      success(res) {
        if (!res.confirm) { that.setData({ busy: false }); return }
        api
          .cancelOrder(that.orderId)
          .then(function () {
            that.setData({ busy: false })
            wx.showToast({ title: '已撤销', icon: 'success' })
            that.load()
          })
          .catch(function (err) {
            that.setData({ busy: false })
            wx.showModal({ title: '撤销失败', content: api.friendly(err), showCancel: false })
          })
      },
      fail() { that.setData({ busy: false }) },
    })
  },

  reorder() {
    const kitchenId = this.data.kitchenId
    const items = this.data.items || []
    if (!kitchenId || !items.length) return
    const valid = items.filter(function (row) {
      return Number(row.dish_id) > 0 && Number(row.quantity) > 0
    })
    if (!valid.length) {
      wx.showToast({ title: '这单菜品已不在菜单里', icon: 'none' })
      return
    }
    const next = cart.readCart(kitchenId)
    valid.forEach(function (row) {
      const id = Number(row.dish_id)
      const prev = next[id]
      next[id] = {
        id: id,
        kitchen_id: kitchenId,
        name: row.dish_name || (prev && prev.name) || '菜品',
        count: (prev ? Number(prev.count || 0) : 0) + Number(row.quantity || 1),
      }
    })
    cart.writeCart(kitchenId, next)
    haptics.light()
    wx.showToast({ title: '已装回点菜清单', icon: 'success', duration: 900 })
    wx.navigateTo({ url: '/pages/cart/cart?kitchenId=' + kitchenId })
  },

  goMenu() {
    if (!this.data.kitchenId) return
    wx.navigateTo({ url: '/pages/menu/menu?kitchenId=' + this.data.kitchenId })
  },

  goChef() {
    const app = getApp()
    if (app && app.globalData) app.globalData.ordersSegment = 'received'
    wx.switchTab({ url: '/pages/orders/orders' })
  },
})
