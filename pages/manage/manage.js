const api = require('../../utils/api')
const sorting = require('../../utils/inline-sort')
const { confirmDelete } = require('../../utils/confirm-delete')

Page({
  data: {
    ...sorting.initialData,
    canManage: false,
    categoryBusy: false,
    kitchenId: 0,
    loading: true,
    error: '',
    kitchen: null,
    categories: [],
    dishes: [],
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
        const dishes = payload.result[2] || []
        const ingredients = payload.result[3] || []
        const alerts = payload.result[4] || []
        const orders = payload.result[5] || []
        const members = payload.result[6] || []
        const canManage = kitchen.owner_id === payload.user.id || members.some(row => row.user_id === payload.user.id)
        if (!canManage) throw new Error('只有厨房拥有者和共有人可以管理菜单')
        if (that._unloaded) return
        const low = ingredients.filter(function (item) {
          const stock = Number(item.stock || 0)
          const threshold = Number(item.alert_threshold || 0)
          return stock <= 0 || (threshold > 0 && stock <= threshold)
        })
        that.setData({
          kitchen: kitchen,
          canManage,
          categories: categories,
          dishes: dishes,
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
      .catch(function (err) {
        that.setData({ loading: false, error: api.friendly(err) })
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
