const api = require('../../utils/api')
const sort = require('../../utils/menu-sort')

Page({
  data: {
    title: '调整顺序', loading: true, canManage: false, error: '',
    items: [], dirty: false, saving: false, dragging: false,
    dragId: '', dragName: '', dragTop: 0, dragHeight: 0, scrollTop: 0,
  },

  onLoad(options) {
    this.kitchenId = Number(options && options.kitchenId)
    this.kind = options && options.kind
    if (!this.kitchenId || !['categories', 'dishes'].includes(this.kind)) {
      this.setData({ loading: false, error: '没有指定有效的厨房和排序类型' })
      return
    }
    const title = this.kind === 'categories' ? '分类排序' : '菜品排序'
    this.setData({ title })
    wx.setNavigationBarTitle({ title })
    this.load()
  },

  onHide() { this.endDrag() },
  onUnload() { this._unloaded = true; this.endDrag() },

  async load() {
    if (this.data.saving) return
    this.endDrag()
    this.setData({ loading: true, canManage: false, error: '' })
    try {
      const user = await api.requireUser()
      const [kitchen, members] = await Promise.all([
        api.fetchKitchen(this.kitchenId), api.fetchMembers(this.kitchenId),
      ])
      if (!kitchen || (kitchen.owner_id !== user.id && !members.some(row => row.user_id === user.id))) {
        throw new Error('只有厨房拥有者和共有人可以调整顺序')
      }
      const items = this.kind === 'categories'
        ? await api.fetchCategories({ kitchenId: this.kitchenId })
        : await api.fetchDishes({ kitchenId: this.kitchenId })
      if (this._unloaded) return
      this._originalIds = items.map(item => item.id)
      this._scrollTop = 0
      this.setData({ items, dirty: false, canManage: true, scrollTop: 0 })
    } catch (err) {
      if (!this._unloaded) this.setData({ error: api.friendly(err) })
    } finally {
      if (!this._unloaded) this.setData({ loading: false })
    }
  },

  blocked() { return this.data.loading || this.data.saving || !this.data.canManage },

  moveItem(id, index) {
    if (this.blocked()) return
    const items = sort.move(this.data.items, id, index)
    if (sort.sameIds(items.map(row => row.id), this.data.items.map(row => row.id))) return
    this.setData({ items, dirty: !sort.sameIds(items.map(row => row.id), this._originalIds || []) })
  },

  toTop(event) {
    if (this.data.dragging) return
    this.moveItem(event.currentTarget.dataset.id, 0)
  },
  toBottom(event) {
    if (this.data.dragging) return
    this.moveItem(event.currentTarget.dataset.id, this.data.items.length - 1)
  },

  touchStart(event) {
    if (this.blocked()) return
    this._touchActive = true
    const touch = event.touches && event.touches[0]
    if (touch) this._touchY = touch.clientY
  },

  startDrag(event) {
    if (this.blocked() || !this._touchActive || this.data.items.length < 2) return
    const id = event.currentTarget.dataset.id
    const item = this.data.items.find(row => String(row.id) === String(id))
    if (!item) return
    const ticket = this._dragTicket = (this._dragTicket || 0) + 1
    wx.createSelectorQuery().in(this)
      .select('.sort-scroll').boundingClientRect()
      .select('.sort-row').boundingClientRect()
      .exec(rects => {
        if (ticket !== this._dragTicket || !this._touchActive || this._unloaded || this.blocked()) return
        if (!rects[0] || !rects[1] || !rects[1].height) return
        this._viewport = rects[0]
        this._rowHeight = rects[1].height
        this._dragBefore = this.data.items.slice()
        this.setData({ dragging: true, dragId: id, dragName: item.name, dragHeight: this._rowHeight })
        this.updateDrag()
        this._scrollTimer = setInterval(() => this.autoScroll(), 40)
      })
  },

  touchMove(event) {
    const touch = event.touches && event.touches[0]
    if (!touch) return
    this._touchY = touch.clientY
    if (this.data.dragging) this.updateDrag()
  },

  updateDrag() {
    if (!this.data.dragging || !this._viewport || !Number.isFinite(this._touchY)) return
    const index = sort.targetIndex(this._touchY, this._viewport.top, this._scrollTop || 0, this._rowHeight, this.data.items.length)
    this.moveItem(this.data.dragId, index)
    const top = Math.max(this._viewport.top, Math.min(this._viewport.bottom - this._rowHeight, this._touchY - this._rowHeight / 2))
    this.setData({ dragTop: top })
  },

  onScroll(event) {
    this._scrollTop = event.detail.scrollTop
    if (this.data.dragging) this.updateDrag()
  },

  autoScroll() {
    if (!this.data.dragging || !this._viewport) return
    const edge = Math.min(48, this._viewport.height / 4)
    const direction = this._touchY < this._viewport.top + edge ? -1
      : this._touchY > this._viewport.bottom - edge ? 1 : 0
    if (!direction) return
    const max = Math.max(0, this.data.items.length * this._rowHeight - this._viewport.height)
    const next = Math.max(0, Math.min(max, (this._scrollTop || 0) + direction * 12))
    if (next === this._scrollTop) return
    this._scrollTop = next
    this.setData({ scrollTop: next })
    this.updateDrag()
  },

  endDrag() {
    this._touchActive = false
    this._dragTicket = (this._dragTicket || 0) + 1
    if (this._scrollTimer) clearInterval(this._scrollTimer)
    this._scrollTimer = null
    if (!this._unloaded) this.setData({ dragging: false, dragId: '' })
  },

  cancelDrag() {
    if (this.data.dragging && this._dragBefore) {
      const items = this._dragBefore
      this.setData({ items, dirty: !sort.sameIds(items.map(row => row.id), this._originalIds || []) })
    }
    this.endDrag()
  },

  refresh() {
    if (this.data.loading || this.data.saving || this.data.dragging) return
    if (!this.data.dirty) { this.load(); return }
    wx.showModal({ title: '重新加载顺序？', content: '本次未保存的调整会被丢弃。', success: res => {
      if (res.confirm && !this.data.saving) this.load()
    } })
  },

  cancel() {
    if (this.data.saving || this.data.dragging) return
    if (!this.data.dirty) { wx.navigateBack(); return }
    wx.showModal({ title: '放弃调整？', content: '当前顺序尚未保存。', success: res => {
      if (res.confirm && !this.data.saving) wx.navigateBack()
    } })
  },

  async save() {
    if (this.blocked() || this.data.dragging || !this.data.dirty) return
    this.setData({ saving: true, error: '' })
    const ids = this.data.items.map(row => row.id)
    try {
      const result = await api.reorderKitchenItems(this.kitchenId, this.kind, ids, this._originalIds.slice())
      if (!result || result.ok !== true) throw new Error('未能确认排序结果，请重试或刷新列表')
      this._originalIds = ids
      if (this._unloaded) return
      this.setData({ dirty: false })
      wx.showToast({ title: '顺序已保存', icon: 'success' })
      wx.navigateBack()
    } catch (err) {
      if (!this._unloaded) this.setData({ error: api.friendly(err) })
    } finally {
      if (!this._unloaded) this.setData({ saving: false })
    }
  },
})
