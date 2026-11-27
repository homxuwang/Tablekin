const api = require('../../utils/api')
const recent = require('../../utils/recent')

function pad(n) {
  return n < 10 ? '0' + n : String(n)
}

function clock(value) {
  if (!value) return ''
  const date = new Date(value)
  if (isNaN(date.getTime())) return ''
  return pad(date.getHours()) + ':' + pad(date.getMinutes())
}

// 顾客首页：找厨房点菜。大厨那一侧的事情都放在「下厨」页里。
Page({
  data: {
    loading: true,
    error: '',
    lastKitchen: null,
    ongoing: [],
    kitchens: [],
    mineCount: 0,
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

  onShareAppMessage() {
    return { title: '吃好喝好 · 今天想吃什么？', path: '/pages/home/home' }
  },

  syncTabBar() {
    if (typeof this.getTabBar === 'function' && this.getTabBar()) {
      this.getTabBar().setData({ active: 0 })
    }
  },

  load() {
    const that = this
    this.setData({ loading: true, error: '' })
    return api
      .requireUser()
      .then(function () {
        return Promise.all([
          api.fetchMyKitchens(),
          api.searchKitchens(''),
          api.fetchMyOrders({ limit: 30 }).catch(function () {
            return []
          }),
        ])
      })
      .then(function (result) {
        const mine = result[0] || []
        const discover = result[1] || []
        const orders = result[2] || []
        const mineIds = {}
        mine.forEach(function (item) {
          mineIds[item.id] = true
        })
        // 顾客视角里不重复展示自己开的厨房，那些在「下厨」里
        const others = discover.filter(function (item) {
          return !mineIds[item.id]
        })
        const ongoing = orders.filter(function (order) {
          return order.status === 'pending' || order.status === 'accepted'
        })
        const lastId = recent.readLastKitchen()
        const ids = []
        others.forEach(function (item) {
          if (ids.indexOf(item.id) < 0) ids.push(item.id)
        })
        ongoing.forEach(function (order) {
          if (order.kitchen_id && ids.indexOf(order.kitchen_id) < 0) ids.push(order.kitchen_id)
        })
        if (lastId && ids.indexOf(lastId) < 0) ids.push(lastId)
        const otherIds = others.map(function (item) {
          return item.id
        })
        const orderIds = ongoing.map(function (order) {
          return order.id
        })
        return Promise.all([
          ids.length
            ? api.fetchKitchensByIds(ids).catch(function () {
                return []
              })
            : Promise.resolve([]),
          otherIds.length
            ? api.countPublicDishes(otherIds).catch(function () {
                return {}
              })
            : Promise.resolve({}),
          orderIds.length
            ? api.fetchOrderItems(orderIds).catch(function () {
                return []
              })
            : Promise.resolve([]),
        ]).then(function (extra) {
          return {
            mineCount: mine.length,
            others: others,
            ongoing: ongoing,
            lastId: lastId,
            kitchens: extra[0] || [],
            counts: extra[1] || {},
            items: extra[2] || [],
          }
        })
      })
      .then(function (payload) {
        const kitchenById = {}
        payload.kitchens.forEach(function (kitchen) {
          kitchenById[kitchen.id] = kitchen
        })
        const itemsByOrder = {}
        payload.items.forEach(function (row) {
          if (!itemsByOrder[row.order_id]) itemsByOrder[row.order_id] = []
          itemsByOrder[row.order_id].push(row)
        })

        const ongoing = payload.ongoing.map(function (order) {
          const status = api.orderStatus(order)
          const rows = itemsByOrder[order.id] || []
          const total = rows.reduce(function (sum, row) {
            return sum + Number(row.quantity || 0)
          }, 0)
          const kitchen = kitchenById[order.kitchen_id]
          return Object.assign({}, order, {
            kitchenName: kitchen ? kitchen.name : '某个厨房',
            statusText: status.text,
            statusClass: 'st-' + status.tone,
            mealTimeText: api.mealScheduleText(order),
            timeText: clock(order.created_at),
            dishesText: rows
              .slice(0, 3)
              .map(function (row) {
                return row.dish_name
              })
              .join('、'),
            total: total,
          })
        })

        const lastKitchen = payload.lastId ? kitchenById[payload.lastId] : null
        if (payload.lastId && !lastKitchen) recent.clearLastKitchen()

        const kitchens = payload.others
          .map(function (kitchen) {
            const count = payload.counts[kitchen.id] || 0
            return Object.assign({}, kitchen, {
              initial: String(kitchen.name || '厨').slice(0, 1),
              dishCount: count,
              dishText: count > 0 ? count + ' 道菜在售' : '还没上菜',
            })
          })
          .sort(function (a, b) {
            return b.dishCount - a.dishCount
          })

        that.setData({
          loading: false,
          mineCount: payload.mineCount,
          ongoing: ongoing,
          lastKitchen: lastKitchen
            ? Object.assign({}, lastKitchen, {
                initial: String(lastKitchen.name || '厨').slice(0, 1),
              })
            : null,
          kitchens: kitchens,
        })
      })
      .catch(function (err) {
        that.setData({ loading: false, error: api.friendly(err) })
      })
  },

  goSearch() {
    wx.navigateTo({ url: '/pages/search/search' })
  },

  openMenu(event) {
    wx.navigateTo({ url: '/pages/menu/menu?kitchenId=' + Number(event.currentTarget.dataset.id) })
  },

  openOrder(event) {
    wx.navigateTo({ url: '/pages/order-detail/order-detail?id=' + Number(event.currentTarget.dataset.id) })
  },

  // 顾客也能是大厨：切到「下厨」开一个自己的厨房
  goChef() {
    wx.switchTab({ url: '/pages/chef/chef' })
  },
})
