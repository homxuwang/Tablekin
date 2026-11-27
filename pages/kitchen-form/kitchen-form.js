const api = require('../../utils/api')
const { confirmDelete } = require('../../utils/confirm-delete')
const recent = require('../../utils/recent')

Page({
  data: {
    loading: false,
    saving: false,
    deleting: false,
    error: '',
    editMode: false,
    kitchenId: 0,
    isOwner: false,
    form: { name: '', description: '', is_public: true },
    nickname: '',
  },

  onLoad(options) {
    const kitchenId = Number((options && options.kitchenId) || 0)
    this.kitchenId = kitchenId
    this.setData({ kitchenId: kitchenId, editMode: !!kitchenId })
    if (kitchenId) {
      wx.setNavigationBarTitle({ title: '厨房资料' })
      this.load()
    } else {
      wx.setNavigationBarTitle({ title: '新建厨房' })
      this.setData({ loading: false })
    }
  },

  load() {
    const that = this
    this.setData({ loading: true, error: '' })
    return api
      .requireUser()
      .then(function (user) {
        return api.fetchKitchen(that.kitchenId).then(function (kitchen) {
          return { user: user, kitchen: kitchen }
        })
      })
      .then(function (payload) {
        const kitchen = payload.kitchen
        if (!kitchen) throw new Error('这个厨房不存在，或者你还不是它的成员')
        const isOwner = kitchen.owner_id === payload.user.id
        that.setData({
          loading: false,
          isOwner: isOwner,
          form: {
            name: kitchen.name || '',
            description: kitchen.description || '',
            is_public: !!kitchen.is_public,
          },
        })
      })
      .catch(function (err) {
        that.setData({ loading: false, error: api.friendly(err) })
      })
  },

  onInput(event) {
    const patch = {}
    patch['form.' + event.currentTarget.dataset.field] = event.detail.value
    this.setData(patch)
  },

  onNicknameInput(event) {
    this.setData({ nickname: event.detail.value })
  },

  onPublicChange(event) {
    this.setData({ 'form.is_public': !!event.detail.value })
  },

  save() {
    const that = this
    if (this.data.saving || this.data.deleting) return
    if (this.data.editMode && !this.data.isOwner) {
      wx.showToast({ title: '只有厨房拥有者能修改资料', icon: 'none' })
      return
    }
    const form = this.data.form
    const name = String(form.name || '').trim()
    if (!name) {
      wx.showToast({ title: '请先给厨房起个名字', icon: 'none' })
      return
    }
    this.setData({ saving: true })
    const payload = {
      name: name,
      description: String(form.description || '').trim() || null,
      is_public: !!form.is_public,
    }
    const task = this.data.editMode
      ? api.updateKitchen(this.kitchenId, payload)
      : api.createKitchen(
          Object.assign({}, payload, { nickname: String(this.data.nickname || '').trim() })
        )
    task
      .then(function (kitchen) {
        const id = that.kitchenId || (kitchen && kitchen.id)
        that.setData({ saving: false })
        wx.showToast({ title: that.data.editMode ? '已保存' : '已创建', icon: 'success' })
        setTimeout(function () {
          if (that.data.editMode) {
            wx.navigateBack()
          } else {
            wx.redirectTo({ url: '/pages/manage/manage?kitchenId=' + id })
          }
        }, 700)
      })
      .catch(function (err) {
        that.setData({ saving: false })
        wx.showModal({ title: '保存失败', content: api.friendly(err), showCancel: false })
      })
  },

  async removeKitchen() {
    if (!this.data.editMode || !this.data.isOwner || this.data.saving || this.data.deleting) return
    this.setData({ deleting: true })
    try {
      if (!await confirmDelete({ title: '删除「' + this.data.form.name + '」厨房？', content: '厨房下的分类、菜品、食材、订单和成员关系都会一起删除，无法恢复。' }, wx)) return
      await api.deleteKitchen(this.kitchenId)
      recent.forgetIf(this.kitchenId)
      this.setData({ isOwner: false })
      wx.showToast({ title: '已删除', icon: 'success' })
      wx.switchTab({ url: '/pages/chef/chef' })
    } catch (err) {
      wx.showModal({ title: '删除失败', content: api.friendly(err), showCancel: false })
    } finally {
      this.setData({ deleting: false })
    }
  },

  goBack() {
    wx.navigateBack()
  },
})
