const api = require('../../utils/api')
const dishImages = require('../../utils/dish-images')
const haptics = require('../../utils/haptics')
const sorting = require('../../utils/inline-sort')
const { confirmDelete } = require('../../utils/confirm-delete')

function filterDishesByCat(dishes, catFilter) {
  const list = dishes || []
  if (!catFilter || catFilter === 'all') return list
  if (catFilter === 'uncat') {
    return list.filter(function (dish) {
      return !dish.category_id
    })
  }
  const targetId = Number(catFilter)
  return list.filter(function (dish) {
    return Number(dish.category_id || 0) === targetId
  })
}

Page({
  data: {
    ...sorting.initialData,
    canManage: false,
    categoryBusy: false,
    dishBusyId: 0,
    kitchenId: 0,
    loading: true,
    error: '',
    kitchen: null,
    categories: [],
    dishes: [],
    filteredDishes: [],
    catFilter: 'all',
    hasUncatDishes: false,
    newCategoryName: '',
    addingCategory: false,
    total: 0,
    publicCount: 0,
    ingredientCount: 0,
    lowIngredientCount: 0,
    lowIngredientNames: '',
    alertCount: 0,
    pendingCount: 0,
    memberCount: 0,
    isOwner: false,
  },

  ...sorting.methods(api, typeof wx === 'undefined' ? null : wx),
  onHide() { this.sortEndDrag() },
  onUnload() { this._unloaded = true; this.sortEndDrag() },

  onLoad(options) {
    this.kitchenId = Number((options && options.kitchenId) || 0)
    this.setData({ kitchenId: this.kitchenId })
  },

  onShow() {
    if (!this.kitchenId) {
      this.setData({ loading: false, error: '没有指定厨房，请从首页重新进入' })
      return
    }
    this.load()
  },

  onPullDownRefresh() {
    this.load().then(function () {
      wx.stopPullDownRefresh()
    })
  },

  onShareAppMessage() {
    const kitchen = this.data.kitchen
    return {
      title: kitchen ? '来「' + kitchen.name + '」点菜' : '来我家厨房点菜',
      path: '/pages/menu/menu?kitchenId=' + this.data.kitchenId,
    }
  },

  load() {
    if (this.data.sortKind || this.data.categoryBusy || this._unloaded) return Promise.resolve()
    const that = this
    const id = this.kitchenId
    this.setData({ loading: true, error: '', canManage: false })
    return api
      .requireUser()
      .then(function (user) {
        return Promise.all([
          api.fetchKitchen(id),
          api.fetchCategories({ kitchenId: id }),
          api.fetchDishes({ kitchenId: id }),
          api.fetchIngredients({ kitchenId: id }),
          api.fetchShortageAlerts(id),
          api.fetchOrders({ kitchenId: id, status: 'pending', limit: 100 }),
          api.fetchMembers(id),
        ]).then(function (result) {
          return { user: user, result: result }
        })
      })
      .then(function (payload) {
        const kitchen = payload.result[0]
        if (!kitchen) throw new Error('这个厨房不存在，或者你还不是它的成员')
        const categories = payload.result[1] || []
        const rawDishes = payload.result[2] || []
        const ingredients = payload.result[3] || []
        const alerts = payload.result[4] || []
        const orders = payload.result[5] || []
        const members = payload.result[6] || []
        const canManage = kitchen.owner_id === payload.user.id || members.some(row => row.user_id === payload.user.id)
        if (!canManage) throw new Error('只有厨房拥有者和共有人可以管理菜单')
        const coverPaths = rawDishes.map(function (dish) {
          return dishImages.paths(dish)[0]
        })
        const signTask = typeof api.signImageUrls === 'function'
          ? api.signImageUrls(coverPaths).catch(function () { return {} })
          : Promise.resolve({})
        return signTask.then(function (urls) {
          if (that._unloaded) return
          const dishes = rawDishes.map(function (dish) {
            const firstPath = dishImages.paths(dish)[0]
            return Object.assign({}, dish, {
              initial: String(dish.name || '菜').slice(0, 1),
              imageUrl: (urls && firstPath && urls[firstPath]) || '',
            })
          })
          const low = ingredients.filter(function (item) {
            const stock = Number(item.stock || 0)
            const threshold = Number(item.alert_threshold || 0)
            return stock <= 0 || (threshold > 0 && stock <= threshold)
          })
          const hasUncatDishes = dishes.some(function (dish) {
            return !dish.category_id
          })
          const catIds = categories.map(function (c) { return String(c.id) })
          let nextCatFilter = that.data.catFilter || 'all'
          if (nextCatFilter === 'uncat' && !hasUncatDishes) nextCatFilter = 'all'
          else if (nextCatFilter !== 'all' && nextCatFilter !== 'uncat' && catIds.indexOf(String(nextCatFilter)) < 0) nextCatFilter = 'all'
          that.setData({
            kitchen: kitchen,
            canManage,
            categories: categories,
            dishes: dishes,
            catFilter: nextCatFilter,
            hasUncatDishes: hasUncatDishes,
            filteredDishes: filterDishesByCat(dishes, nextCatFilter),
            loading: false,
            isOwner: kitchen.owner_id === payload.user.id,
            total: dishes.length,
            publicCount: dishes.filter(function (dish) {
              return dish.is_public
            }).length,
            ingredientCount: ingredients.length,
            lowIngredientCount: low.length,
            lowIngredientNames: low
              .map(function (item) {
                return item.name
              })
              .join('、'),
            alertCount: alerts.length,
            pendingCount: orders.filter(function (order) {
              return order.status === 'pending'
            }).length,
            memberCount: members.length,
          })
          wx.setNavigationBarTitle({ title: kitchen.name || '厨房管理' })
        })
      })
      .catch(function (err) {
        that.setData({ loading: false, error: api.friendly(err) })
      })
  },

  pickCatFilter(event) {
    const id = String(event.currentTarget.dataset.id || 'all')
    if (id === this.data.catFilter) return
    haptics.light()
    this.setData({
      catFilter: id,
      filteredDishes: filterDishesByCat(this.data.dishes, id),
    })
  },

  toggleDishAvailable(event) {
    if (this.data.sortKind || this.data.categoryBusy || this.data.dishBusyId || !this.data.canManage) return
    const that = this
    const id = Number(event.currentTarget.dataset.id)
    const target = this.data.dishes.filter(function (item) {
      return item.id === id
    })[0]
    if (!target) return
    const next = !target.is_available
    haptics.light()
    this.setData({ dishBusyId: id })
    return api
      .updateDish(id, { is_available: next })
      .then(function () {
        if (that._unloaded) return
        const dishes = that.data.dishes.map(function (dish) {
          return dish.id === id ? Object.assign({}, dish, { is_available: next }) : dish
        })
        that.setData({
          dishes: dishes,
          filteredDishes: filterDishesByCat(dishes, that.data.catFilter),
          dishBusyId: 0,
        })
        haptics.success()
        wx.showToast({ title: next ? '已恢复在售' : '已设为下架', icon: 'none' })
      })
      .catch(function (err) {
        if (that._unloaded) return
        that.setData({ dishBusyId: 0 })
        wx.showModal({ title: '修改失败', content: api.friendly(err), showCancel: false })
      })
  },

  onNewCategoryInput(event) {
    this.setData({ newCategoryName: event.detail.value })
  },

  addCategory() {
    if (this.data.sortKind || this.data.categoryBusy || !this.data.canManage) return
    const that = this
    const name = String(this.data.newCategoryName || '').trim()
    if (!name) {
      wx.showToast({ title: '请先输入分类名称', icon: 'none' })
      return
    }
    if (this.data.addingCategory) return
    this.setData({ addingCategory: true })
    api
      .createCategory({
        kitchen_id: this.kitchenId,
        name: name,
        sort_order: this.data.categories.length,
        is_public: true,
      })
      .then(function () {
        that.setData({ newCategoryName: '', addingCategory: false })
        wx.showToast({ title: '已添加', icon: 'success' })
        that.load()
      })
      .catch(function (err) {
        that.setData({ addingCategory: false })
        wx.showModal({ title: '添加失败', content: api.friendly(err), showCancel: false })
      })
  },

  toggleCategoryPublic(event) {
    if (this.data.sortKind || this.data.categoryBusy || !this.data.canManage) return
    const that = this
    const id = Number(event.currentTarget.dataset.id)
    api
      .updateCategory(id, { is_public: !!event.detail.value })
      .then(function () {
        that.load()
      })
      .catch(function (err) {
        wx.showModal({ title: '修改失败', content: api.friendly(err), showCancel: false })
        that.load()
      })
  },

  async removeCategory(event) {
    if (this.data.sortKind || this.data.categoryBusy || this.data.addingCategory || this.data.loading || !this.data.canManage) return
    const id = Number(event.currentTarget.dataset.id)
    const target = this.data.categories.filter(function (item) {
      return item.id === id
    })[0]
    if (!target) return
    this.setData({ categoryBusy: true })
    try {
      if (!await confirmDelete({ title: '删除分类「' + target.name + '」？', content: '分类下的菜品会变成未分类，菜品本身保留。' }, wx) || this._unloaded) return
      await api.deleteCategory(id)
      wx.showToast({ title: '已删除', icon: 'success' })
      this.setData({ categoryBusy: false })
      await this.load()
    } catch (err) {
      wx.showModal({ title: '删除失败', content: api.friendly(err), showCancel: false })
    } finally {
      if (!this._unloaded) this.setData({ categoryBusy: false })
    }
  },

  openDish(event) {
    if (this.data.sortKind || this.data.categoryBusy) return
    wx.navigateTo({
      url:
        '/pages/dish/dish?id=' +
        Number(event.currentTarget.dataset.id) +
        '&kitchenId=' +
        this.kitchenId +
        '&mode=edit',
    })
  },

  newDish() {
    if (this.data.sortKind || this.data.categoryBusy) return
    wx.navigateTo({ url: '/pages/dish/dish?kitchenId=' + this.kitchenId + '&mode=edit' })
  },

  goIngredients() {
    wx.navigateTo({ url: '/pages/ingredients/ingredients?kitchenId=' + this.kitchenId })
  },

  goOrders() {
    const app = getApp()
    if (app && app.globalData) app.globalData.ordersSegment = 'received'
    wx.switchTab({ url: '/pages/orders/orders' })
  },

  goMembers() {
    wx.navigateTo({ url: '/pages/members/members?kitchenId=' + this.kitchenId })
  },

  goSettings() {
    wx.navigateTo({ url: '/pages/kitchen-form/kitchen-form?kitchenId=' + this.kitchenId })
  },

  goMenu() {
    wx.navigateTo({ url: '/pages/menu/menu?kitchenId=' + this.kitchenId })
  },

  goHome() {
    wx.switchTab({ url: '/pages/chef/chef' })
  },
})
