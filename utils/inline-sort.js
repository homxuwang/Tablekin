const order = require('./menu-sort')

const initialData = {
  sortKind: '', sortItems: [], sortDirty: false, sortSaving: false,
  sortDragging: false, sortDragId: '', sortDragName: '', sortDragTop: 0,
  sortDragHeight: 0, sortScrollTop: 0, sortError: '',
}

function methods(api, wxClient) {
  return {
    openSort(event) {
      if (this.data.loading || !this.data.canManage || this.data.sortKind || this.data.addingCategory || this.data.categoryBusy) return
      const kind = event.currentTarget.dataset.kind
      if (!['categories', 'dishes'].includes(kind)) return
      this._sortOriginalRows = this.data[kind].slice()
      this._sortOriginalIds = this._sortOriginalRows.map(row => row.id)
      this._sortScroll = 0
      this.setData({ ...initialData, sortKind: kind, sortItems: this._sortOriginalRows.slice() })
    },

    sortMove(id, index) {
      if (!this.data.sortKind || this.data.sortSaving) return
      const items = order.move(this.data.sortItems, id, index)
      this.setData({ sortItems: items, sortDirty: !order.sameIds(items.map(row => row.id), this._sortOriginalIds) })
    },
    sortTop(event) {
      if (!this.data.sortDragging) this.sortMove(event.currentTarget.dataset.id, 0)
    },
    sortBottom(event) {
      if (!this.data.sortDragging) this.sortMove(event.currentTarget.dataset.id, this.data.sortItems.length - 1)
    },

    sortTouchStart(event) {
      if (this.data.sortSaving || this.data.sortDragging) return
      const touch = event.touches && event.touches[0]
      this._sortTouchActive = !!touch
      if (touch) this._sortTouchY = touch.clientY
    },
    sortStartDrag(event) {
      if (this.data.sortSaving || this.data.sortDragging || !this._sortTouchActive || this.data.sortItems.length < 2) return
      const id = event.currentTarget.dataset.id
      const row = this.data.sortItems.find(item => String(item.id) === String(id))
      if (!row) return
      const ticket = this._sortTicket = (this._sortTicket || 0) + 1
      wxClient.createSelectorQuery().in(this)
        .select('.inline-sort-scroll').boundingClientRect()
        .select('.inline-sort-row').boundingClientRect()
        .exec(rects => {
          if (ticket !== this._sortTicket || !this._sortTouchActive || this._unloaded || !this.data.sortKind || this.data.sortSaving) return
          if (!rects[0] || !rects[1] || !rects[1].height) return
          this._sortViewport = rects[0]
          this._sortRowHeight = rects[1].height
          this._sortBeforeDrag = this.data.sortItems.slice()
          this.setData({ sortDragging: true, sortDragId: id, sortDragName: row.name, sortDragHeight: this._sortRowHeight })
          this.sortUpdateDrag()
          this._sortTimer = setInterval(() => this.sortAutoScroll(), 40)
        })
    },
    sortTouchMove(event) {
      const touch = event.touches && event.touches[0]
      if (!touch) return
      this._sortTouchY = touch.clientY
      if (this.data.sortDragging) this.sortUpdateDrag()
    },
    sortUpdateDrag() {
      if (!this.data.sortDragging || !this._sortViewport) return
      const viewport = this._sortViewport
      this.sortMove(this.data.sortDragId, order.targetIndex(this._sortTouchY, viewport.top, this._sortScroll || 0, this._sortRowHeight, this.data.sortItems.length))
      this.setData({ sortDragTop: Math.max(viewport.top, Math.min(viewport.bottom - this._sortRowHeight, this._sortTouchY - this._sortRowHeight / 2)) })
    },
    sortOnScroll(event) {
      this._sortScroll = event.detail.scrollTop
      if (this.data.sortDragging) this.sortUpdateDrag()
    },
    sortAutoScroll() {
      if (!this.data.sortDragging || !this._sortViewport) return
      const viewport = this._sortViewport
      const edge = Math.min(48, viewport.height / 4)
      const direction = this._sortTouchY < viewport.top + edge ? -1 : this._sortTouchY > viewport.bottom - edge ? 1 : 0
      if (!direction) return
      const max = Math.max(0, this.data.sortItems.length * this._sortRowHeight - viewport.height)
      const next = Math.max(0, Math.min(max, (this._sortScroll || 0) + direction * 12))
      if (next === this._sortScroll) return
      this._sortScroll = next
      this.setData({ sortScrollTop: next })
      this.sortUpdateDrag()
    },
    sortEndDrag() {
      this._sortTouchActive = false
      this._sortTicket = (this._sortTicket || 0) + 1
      if (this._sortTimer) clearInterval(this._sortTimer)
      this._sortTimer = null
      if (!this._unloaded) this.setData({ sortDragging: false, sortDragId: '' })
    },
    sortCancelDrag() {
      if (this.data.sortDragging && this._sortBeforeDrag) {
        const rows = this._sortBeforeDrag
        this.setData({ sortItems: rows, sortDirty: !order.sameIds(rows.map(row => row.id), this._sortOriginalIds) })
      }
      this.sortEndDrag()
    },
    sortCancel() {
      if (this.data.sortSaving || this.data.sortDragging) return
      this.sortEndDrag()
      this.setData({ ...initialData })
    },
    async sortReload() {
      if (this.data.sortSaving || this.data.sortDragging) return
      wxClient.showModal({ title: '重新加载顺序？', content: '本次未保存的调整会被丢弃。', success: result => {
        if (!result.confirm || this.data.sortSaving || this._unloaded) return
        this.sortCancel()
        this.load()
      } })
    },
    async sortSave() {
      if (!this.data.sortKind || !this.data.canManage || this.data.sortSaving || this.data.sortDragging || !this.data.sortDirty) return
      const kind = this.data.sortKind
      const rows = this.data.sortItems.slice()
      this.setData({ sortSaving: true, sortError: '' })
      try {
        const result = await api.reorderKitchenItems(this.kitchenId, kind, rows.map(row => row.id), this._sortOriginalIds.slice())
        if (!result || result.ok !== true) throw new Error('未能确认排序结果，请重试或刷新')
        if (this._unloaded) return
        this.setData({ [kind]: rows.map((row, index) => ({ ...row, sort_order: index })), ...initialData })
        wxClient.showToast({ title: '顺序已保存', icon: 'success' })
      } catch (err) {
        if (!this._unloaded) this.setData({ sortError: api.friendly(err) })
      } finally {
        if (!this._unloaded) this.setData({ sortSaving: false })
      }
    },
  }
}

module.exports = { initialData, methods }
