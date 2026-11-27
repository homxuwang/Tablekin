const api = require('../../utils/api')

// 大厨这一侧：我开的 / 我参与的厨房，加上要处理的事。
// 顾客那一侧的事情都在「点菜」页里。
Page({
  data: {
    loading: true,
    error: '',
    kitchens: [],
    todos: [],
    pendingTotal: 0,
    alertTotal: 0,
  },

  onShow() {
    this.syncTabBar()
    this.load()
  },

  onPullDownRefresh() {
    this.load().then(function () {
      wx.stopPullDownRefresh()
    })
  },

  // 每张卡片上的「分享给家人」按钮会带上自己的 data-id，这里按 id 生成对应链接
  onShareAppMessage(options) {
    const dataset = options && options.target && options.target.dataset
    const id = Number((dataset && dataset.id) || 0)
    const kitchen = this.findKitchen(id)
    if (kitchen) {
      return {
        title: '来「' + kitchen.name + '」点菜吧',
        path: '/pages/menu/menu?kitchenId=' + kitchen.id,
      }
    }
    return { title: '吃好喝好 · 我也在家做饭', path: '/pages/home/home' }
  },

  syncTabBar() {
    if (typeof this.getTabBar === 'function' && this.getTabBar()) {
      this.getTabBar().setData({ active: 1 })
    }
  },

  findKitchen(id) {
    return (this.data.kitchens || []).filter(function (item) {
      return item.id === id
    })[0]
  },

  load() {
    const that = this
    this.setData({ loading: true, error: '' })
    return api
      .requireUser()
      .then(function () {
        return api.fetchMyKitchens()
      })
      .then(function (mine) {
        const ids = mine.map(function (item) {
          return item.id
        })
        if (!ids.length) return { mine: [], badges: {}, dishes: [] }
        return Promise.all([
          api.fetchKitchenBadges(ids),
          api.fetchDishes({ kitchenIds: ids }).catch(function () {
            return []
          }),
        ]).then(function (result) {
          return { mine: mine, badges: result[0] || {}, dishes: result[1] || [] }
        })
      })
      .then(function (payload) {
        const dishCount = {}
        payload.dishes.forEach(function (dish) {
          dishCount[dish.kitchen_id] = (dishCount[dish.kitchen_id] || 0) + 1
        })
        let pendingTotal = 0
        let alertTotal = 0
        const todos = []
        const kitchens = payload.mine.map(function (item) {
          const badge = payload.badges[item.id] || { pending: 0, alerts: 0 }
          const pending = Number(badge.pending || 0)
          const alerts = Number(badge.alerts || 0)
          pendingTotal += pending
          alertTotal += alerts
          if (pending || alerts) {
            const parts = []
            if (pending) parts.push(pending + ' 单等你回话')
            if (alerts) parts.push(alerts + ' 条缺料提醒')
            todos.push({ id: item.id, name: item.name, text: parts.join(' · ') })
          }
          const count = dishCount[item.id] || 0
          return Object.assign({}, item, {
            initial: String(item.name || '厨').slice(0, 1),
            roleText: item.role === 'owner' ? '我开的' : '一起管',
            scopeText: item.is_public ? '大家能看到' : '只有自己人',
            dishText: count > 0 ? count + ' 道菜' : '还没写菜单',
            empty: count === 0,
          })
        })
        that.setData({
          loading: false,
          kitchens: kitchens,
          todos: todos,
          pendingTotal: pendingTotal,
          alertTotal: alertTotal,
        })
      })
      .catch(function (err) {
        that.setData({ loading: false, error: api.friendly(err) })
      })
  },

  // 订单页收到这个提示就知道该停在「我收到的」那一栏
  goOrders() {
    const app = getApp()
    if (app && app.globalData) app.globalData.ordersSegment = 'received'
    wx.switchTab({ url: '/pages/orders/orders' })
  },

  openMenu(event) {
    wx.navigateTo({ url: '/pages/menu/menu?kitchenId=' + Number(event.currentTarget.dataset.id) })
  },

  openManage(event) {
    wx.navigateTo({ url: '/pages/manage/manage?kitchenId=' + Number(event.currentTarget.dataset.id) })
  },

  openMembers(event) {
    wx.navigateTo({ url: '/pages/members/members?kitchenId=' + Number(event.currentTarget.dataset.id) })
  },

  newKitchen() {
    wx.navigateTo({ url: '/pages/kitchen-form/kitchen-form' })
  },

  joinKitchen() {
    wx.navigateTo({ url: '/pages/join/join' })
  },
})
