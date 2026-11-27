const api = require('../../utils/api')
const refresh = require('../../utils/live-refresh')
const haptics = require('../../utils/haptics')

function pad(n) {
  return n < 10 ? '0' + n : String(n)
}

function clock(value) {
  if (!value) return ''
  const date = new Date(value)
  if (isNaN(date.getTime())) return ''
  return pad(date.getHours()) + ':' + pad(date.getMinutes())
}

function dayLabel(value) {
  if (!value) return ''
  const date = new Date(value)
  if (isNaN(date.getTime())) return ''
  const week = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']
  return date.getMonth() + 1 + '月' + date.getDate() + '日 ' + week[date.getDay()]
}

// 订单 tab：上半是我作为顾客点出去的单，下半是我作为大厨收到的单。
Page({
  data: {
    loading: true,
    error: '',
    segment: 'mine',
    filterKitchenId: 0,
    statusFilter: 'all',
    activeCount: 0,
    kitchens: [],
    orders: [],
    alerts: [],
    notices: [],
    noticesLimit: 20,
    unreadCount: 0,
    noticesError: '',
    noticesBusy: false,
    busyId: 0,
    totalText: '',
  },

  onLoad() {
    this.allOrders = []
  },

  onShow() {
    this.syncTabBar()
    refresh.start(this, () => this.load({ silent: true }))
    const app = getApp()
    const hint = app && app.globalData ? app.globalData.ordersSegment : ''
    if (app && app.globalData) app.globalData.ordersSegment = ''
    if ((hint === 'received' || hint === 'mine') && hint !== this.data.segment) {
      this.setData({ segment: hint, filterKitchenId: 0, orders: [], alerts: [] }, this.load)
      return
    }
    this.load()
  },

  onHide() { refresh.stop(this) },
  onUnload() { refresh.stop(this) },

  onPullDownRefresh() {
    this.load().then(function () {
      wx.stopPullDownRefresh()
    })
  },

  syncTabBar() {
    if (typeof this.getTabBar === 'function' && this.getTabBar()) {
      this.getTabBar().setData({ active: 2 })
    }
  },

  // 站内未读提醒：新点单、接单、拒单、出餐、撤回都会给相关的人留一条，
  // 这里只读自己的。拿不到提醒不影响订单列表本身，所以失败就静默跳过。
  loadNotices() {
    const that = this
    if (this.data.noticesBusy) return Promise.resolve()
    const version = this._noticesVersion || 0
    return refresh.singleFlight(this, '_noticesRequest', () => Promise.all([
      api.fetchMyNotifications({ unreadOnly: true, limit: that.data.noticesLimit }),
      api.fetchUnreadNotificationCount(),
    ]).then(function (result) {
      if (version !== (that._noticesVersion || 0)) return
      that.setData({ notices: result[0], unreadCount: result[1], noticesError: '' })
      that.updateBadge(result[1])
    }).catch(function (err) {
      that.setData({ noticesError: api.friendly(err) })
    }))
  },

  updateBadge(count) {
    const bar = typeof this.getTabBar === 'function' && this.getTabBar()
    if (bar && typeof bar.setUnreadCount === 'function') bar.setUnreadCount(count)
  },

  moreNotices() {
    this.setData({ noticesLimit: this.data.noticesLimit + 20 })
    return this.loadNotices()
  },

  switchSegment(event) {
    const segment = event.currentTarget.dataset.segment === 'received' ? 'received' : 'mine'
    if (segment === this.data.segment) return
    haptics.light()
    const that = this
    this.setData({ segment: segment, filterKitchenId: 0, statusFilter: 'all', activeCount: 0, orders: [], alerts: [] }, function () {
      that.load()
    })
  },

  pickKitchen(event) {
    const id = Number(event.currentTarget.dataset.id) || 0
    if (id === this.data.filterKitchenId) return
    haptics.light()
    this.setData({ filterKitchenId: id }, this.applyFilter)
  },

  pickStatusFilter(event) {
    const value = String(event.currentTarget.dataset.status || 'all')
    if (value === this.data.statusFilter) return
    haptics.light()
    this.setData({ statusFilter: value }, this.applyFilter)
  },

  load(options) {
    if (this._refreshVisible === false) return Promise.resolve()
    const silent = options && options.silent
    const epoch = this._refreshEpoch || 0
    if (this._ordersRequest && !silent) return this._ordersRequest.then(() => {
      if (epoch === (this._refreshEpoch || 0)) return this.load(options)
    })
    return refresh.singleFlight(this, '_ordersRequest', () => this.loadOrders(!!silent))
  },

  loadOrders(silent) {
    const that = this
    const segment = this.data.segment
    this.loadNotices()
    if (!silent) this.setData({ loading: true, error: '' })
    return api
      .requireUser()
      .then(function () {
        return api.fetchMyKitchens()
      })
      .then(function (mine) {
        const ids = mine.map(function (item) {
          return item.id
        })
        that.kitchenById = {}
        mine.forEach(function (item) {
          that.kitchenById[item.id] = item
        })
        that.setData({
          kitchens: mine.map(function (item) {
            return { id: item.id, name: item.name }
          }),
        })
        if (segment === 'received' && !ids.length) {
          that.allOrders = []
          that.setData({ loading: false, orders: [], alerts: [], totalText: '' })
          return null
        }
        const orderTask =
          segment === 'received' ? api.fetchReceivedOrders(ids) : api.fetchMyOrders({ limit: 60 })
        const alertTask =
          segment === 'received'
            ? api.fetchShortageAlerts().catch(function () {
                return []
              })
            : Promise.resolve([])
        return Promise.all([orderTask, alertTask]).then(function (result) {
          return { orders: result[0] || [], alerts: result[1] || [] }
        })
      })
      .then(function (payload) {
        if (segment !== that.data.segment) return
        if (!payload) return
        const ids = payload.orders.map(function (order) {
          return order.id
        })
        const kitchenIds = []
        payload.orders.forEach(function (order) {
          if (order.kitchen_id && kitchenIds.indexOf(order.kitchen_id) < 0) {
            kitchenIds.push(order.kitchen_id)
          }
        })
        return Promise.all([
          ids.length
            ? api.fetchOrderItems(ids).catch(function () {
                return []
              })
            : Promise.resolve([]),
          kitchenIds.length
            ? api.fetchKitchensByIds(kitchenIds).catch(function () {
                return []
              })
            : Promise.resolve([]),
        ]).then(function (extra) {
          if (segment !== that.data.segment) return
          const names = {}
          extra[1].forEach(function (kitchen) {
            names[kitchen.id] = kitchen.name || ''
          })
          const grouped = {}
          extra[0].forEach(function (row) {
            if (!grouped[row.order_id]) grouped[row.order_id] = []
            grouped[row.order_id].push(row)
          })
          that.allOrders = payload.orders.map(function (order) {
            const status = api.orderStatus(order)
            const rows = grouped[order.id] || []
            const total = rows.reduce(function (sum, row) {
              return sum + Number(row.quantity || 0)
            }, 0)
            return Object.assign({}, order, {
              statusText: status.text,
              statusClass: 'st-' + status.tone,
              mealTimeText: api.mealScheduleText(order),
              timeText: clock(order.created_at),
              dayText: dayLabel(order.created_at),
              kitchenName: names[order.kitchen_id] || '某个厨房',
              items: rows,
              total: total,
              itemCount: rows.length,
            })
          })
          that.setData({
            loading: false,
            error: '',
            alerts: payload.alerts,
            totalText: segment === 'received' ? '共收到 ' + that.allOrders.length + ' 单' : '',
          })
          that.applyFilter()
        })
      })
      .catch(function (err) {
        that.setData({ loading: false, error: api.friendly(err) })
      })
  },

  applyFilter() {
    const filter = this.data.filterKitchenId
    const statusFilter = this.data.statusFilter || 'all'
    const byKitchen = (this.allOrders || []).filter(function (order) {
      if (!filter) return true
      return order.kitchen_id === filter
    })
    const activeCount = byKitchen.filter(function (order) {
      return order.status === 'pending' || order.status === 'accepted'
    }).length
    const list = byKitchen.filter(function (order) {
      if (statusFilter === 'active') return order.status === 'pending' || order.status === 'accepted'
      if (statusFilter === 'done') return order.status !== 'pending' && order.status !== 'accepted'
      return true
    })
    this.setData({ orders: list, activeCount: activeCount })
  },

  findOrder(id) {
    return (this.allOrders || []).filter(function (order) {
      return order.id === id
    })[0]
  },

  openDetail(event) {
    wx.navigateTo({ url: '/pages/order-detail/order-detail?id=' + Number(event.currentTarget.dataset.id) })
  },

  // 大厨：先回一句「收到了」，让人知道这单没被漏掉
  ack(event) {
    const that = this
    const id = Number(event.currentTarget.dataset.id)
    if (this.data.busyId) return
    this.setData({ busyId: id })
    api
      .ackOrder(id)
      .then(function () {
        that.setData({ busyId: 0 })
        wx.showToast({ title: '已回复收到', icon: 'success' })
        that.load()
      })
      .catch(function (err) {
        that.setData({ busyId: 0 })
        wx.showModal({ title: '回复失败', content: api.friendly(err), showCancel: false })
      })
  },

  accept(event) {
    const that = this
    const id = Number(event.currentTarget.dataset.id)
    const order = this.findOrder(id)
    if (!order || this.data.busyId) return
    this.setData({ busyId: id })
    api
      .acceptOrder(id)
      .then(function (result) {
        that.setData({ busyId: 0 })
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
        that.setData({ busyId: 0 })
        wx.showModal({ title: '接单失败', content: api.friendly(err), showCancel: false })
      })
  },

  finish(event) {
    const that = this
    const id = Number(event.currentTarget.dataset.id)
    if (this.data.busyId) return
    this.setData({ busyId: id })
    api
      .finishOrder(id)
      .then(function () {
        that.setData({ busyId: 0 })
        wx.showToast({ title: '已标记出餐', icon: 'success' })
        that.load()
      })
      .catch(function (err) {
        that.setData({ busyId: 0 })
        wx.showModal({ title: '操作失败', content: api.friendly(err), showCancel: false })
      })
  },

  reject(event) {
    const that = this
    const id = Number(event.currentTarget.dataset.id)
    if (this.data.busyId) return
    this.setData({ busyId: id })
    wx.showModal({
      title: '这单做不了？',
      editable: true,
      placeholderText: '原因（可不填），会显示给点菜的人',
      success(res) {
        if (!res.confirm) { that.setData({ busyId: 0 }); return }
        api
          .rejectOrder(id, res.content)
          .then(function () {
            that.setData({ busyId: 0 })
            wx.showToast({ title: '已回复', icon: 'success' })
            that.load()
          })
          .catch(function (err) {
            that.setData({ busyId: 0 })
            wx.showModal({ title: '操作失败', content: api.friendly(err), showCancel: false })
          })
      },
      fail() { that.setData({ busyId: 0 }) },
    })
  },

  cancel(event) {
    const that = this
    const id = Number(event.currentTarget.dataset.id)
    if (this.data.busyId) return
    this.setData({ busyId: id })
    wx.showModal({
      title: '撤回这一单？',
      content: '大厨那边会看到这单已撤回，不用再做了。已经接单的单撤不了，那时候得跟大厨说一声。',
      confirmColor: '#D64545',
      success(res) {
        if (!res.confirm) { that.setData({ busyId: 0 }); return }
        api
          .cancelOrder(id)
          .then(function () {
            that.setData({ busyId: 0 })
            wx.showToast({ title: '已撤销', icon: 'success' })
            that.load()
          })
          .catch(function (err) {
            that.setData({ busyId: 0 })
            wx.showModal({ title: '撤销失败', content: api.friendly(err), showCancel: false })
          })
      },
      fail() { that.setData({ busyId: 0 }) },
    })
  },

  // 点提醒：能落到具体订单就跳订单详情
  async openNotice(event) {
    const orderId = Number(event.currentTarget.dataset.id) || 0
    const noticeId = Number(event.currentTarget.dataset.noticeId) || 0
    if (this.data.noticesBusy || !noticeId) return
    this._noticesVersion = (this._noticesVersion || 0) + 1
    this.setData({ noticesBusy: true })
    try {
      await api.markNotificationsRead([noticeId])
      const count = Math.max(0, this.data.unreadCount - 1)
      this.setData({ notices: this.data.notices.filter(item => item.id !== noticeId), unreadCount: count })
      this.updateBadge(count)
    } catch (err) {
      wx.showToast({ title: '未能标为已读，请稍后重试', icon: 'none' })
    } finally {
      this.setData({ noticesBusy: false })
    }
    if (orderId) wx.navigateTo({ url: '/pages/order-detail/order-detail?id=' + orderId })
  },

  async dismissNotices() {
    if (!this.data.unreadCount || this.data.noticesBusy) return
    this._noticesVersion = (this._noticesVersion || 0) + 1
    this.setData({ noticesBusy: true })
    try {
      await api.markNotificationsRead()
      this.setData({ notices: [], unreadCount: 0 })
      this.updateBadge(0)
      wx.showToast({ title: '已全部标为已读', icon: 'success' })
    } catch (err) {
      wx.showModal({ title: '操作失败', content: api.friendly(err), showCancel: false })
    } finally {
      this.setData({ noticesBusy: false })
    }
  },

  dismissAlerts() {
    const that = this
    const ids = this.data.alerts.map(function (item) {
      return item.id
    })
    if (!ids.length) return
    api
      .markShortageAlertsRead(ids)
      .then(function () {
        that.setData({ alerts: [] })
      })
      .catch(function (err) {
        wx.showModal({ title: '操作失败', content: api.friendly(err), showCancel: false })
      })
  },

  goBrowse() {
    wx.switchTab({ url: '/pages/home/home' })
  },
})
