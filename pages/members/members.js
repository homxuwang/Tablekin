const api = require('../../utils/api')
const recent = require('../../utils/recent')

function pad(n) {
  return n < 10 ? '0' + n : String(n)
}

function formatDate(value) {
  if (!value) return ''
  const date = new Date(value)
  if (isNaN(date.getTime())) return ''
  return date.getFullYear() + '-' + pad(date.getMonth() + 1) + '-' + pad(date.getDate())
}

Page({
  data: {
    kitchenId: 0,
    loading: true,
    error: '',
    kitchen: null,
    members: [],
    inviteCode: '',
    inviteLoading: false,
    inviteBusy: false,
    inviteError: '',
    isOwner: false,
    myMemberId: 0,
    busy: false,
  },

  onLoad(options) {
    this.kitchenId = Number((options && options.kitchenId) || 0)
    this.userId = ''
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

  // 邀请链接就是这张分享卡片：点开它的人会落到「加入厨房」页，凭码入伙。
  onShareAppMessage() {
    const kitchen = this.data.kitchen
    const name = kitchen ? kitchen.name : '我家厨房'
    if (!this.data.isOwner || !this.data.inviteCode || this.data.inviteLoading || this.data.inviteBusy) {
      return { title: '来「' + name + '」点菜吧', path: '/pages/menu/menu?kitchenId=' + this.kitchenId }
    }
    return {
      title: '邀请你加入「' + name + '」，一起管菜单',
      path: '/pages/join/join?code=' + this.data.inviteCode,
    }
  },

  load() {
    const that = this
    const id = this.kitchenId
    this.setData({ loading: true, error: '' })
    return api
      .requireUser()
      .then(function (user) {
        that.userId = user.id
        return Promise.all([api.fetchKitchen(id), api.fetchMembers(id)])
      })
      .then(function (result) {
        const kitchen = result[0]
        if (!kitchen) throw new Error('这个厨房不存在，或者你还不是它的成员')
        const rows = result[1] || []
        const mine = rows.filter(function (row) {
          return row.user_id === that.userId
        })[0]
        const iAmOwner = kitchen.owner_id === that.userId
        that.setData({
          loading: false,
          kitchen: kitchen,
          inviteCode: '',
          isOwner: iAmOwner,
          myMemberId: mine ? mine.id : 0,
          members: rows.map(function (row) {
            const isOwnerRow = row.role === 'owner'
            const isMe = row.user_id === that.userId
            return Object.assign({}, row, {
              roleText: isOwnerRow ? '厨房拥有者' : '共有人',
              displayName: row.nickname || (isOwnerRow ? '厨房主' : '未命名成员'),
              initial: String(row.nickname || (isOwnerRow ? '厨' : '友')).slice(0, 1),
              isMe: isMe,
              isOwnerRow: isOwnerRow,
              joinedText: formatDate(row.created_at),
              // 拥有者可以移出别人；谁都不能把拥有者移出去
              canRemove: iAmOwner && !isOwnerRow && !isMe,
            })
          }),
        })
        // 邀请码不在厨房行里了，只有拥有者取得到，所以单独拉一次
        if (iAmOwner) return that.loadInvite()
      })
      .catch(function (err) {
        that.setData({ loading: false, error: api.friendly(err) })
      })
  },

  // 邀请码由服务端单独保管，只允许拥有者读取
  loadInvite() {
    const that = this
    if (!this.data.isOwner || this.data.inviteBusy) return Promise.resolve()
    const version = this._inviteVersion = (this._inviteVersion || 0) + 1
    this.setData({ inviteLoading: true, inviteError: '' })
    return api
      .getKitchenInvite(this.kitchenId)
      .then(function (data) {
        if (version !== that._inviteVersion) return
        if (!data || !data.invite_code) throw new Error('没有取得邀请码，请重试')
        that.setData({ inviteCode: data.invite_code, inviteLoading: false })
      })
      .catch(function (err) {
        if (version !== that._inviteVersion) return
        that.setData({ inviteCode: '', inviteLoading: false, inviteError: api.friendly(err) })
      })
  },

  // 换一个新码 = 之前发出去的链接和邀请码立刻作废（移出成员后想收回邀请就用它）。
  // 分享卡片本身无法禁止被转发，只能靠换码来控制「谁还能进来」。
  resetInvite() {
    const that = this
    if (!this.data.isOwner || this.data.inviteBusy) return
    this.setData({ inviteBusy: true })
    wx.showModal({
      title: '换一个邀请码',
      content: '换新码之后，之前发出去的邀请链接和邀请码都会失效；已经加入的成员不受影响。',
      confirmText: '换新码',
      async success(res) {
        if (!res.confirm) { that.setData({ inviteBusy: false }); return }
        that._inviteVersion = (that._inviteVersion || 0) + 1
        that.setData({ inviteCode: '', inviteLoading: false, inviteError: '' })
        wx.showLoading({ title: '正在换码', mask: true })
        try {
          const data = await api.resetKitchenInvite(that.kitchenId)
          if (!data || !data.invite_code) throw new Error('换码结果未确认，请重新获取邀请码')
          that.setData({ inviteCode: data.invite_code })
          wx.showToast({ title: '已换新码', icon: 'success' })
        } catch (err) {
          that.setData({ inviteError: api.friendly(err) })
          wx.showModal({ title: '换码结果未确认', content: api.friendly(err) + '。请重新获取当前邀请码，避免再次换码。', showCancel: false })
        } finally {
          wx.hideLoading()
          that.setData({ inviteBusy: false })
        }
      },
      fail() { that.setData({ inviteBusy: false }) },
    })
  },

  copyCode() {
    if (!this.data.isOwner || !this.data.inviteCode || this.data.inviteLoading || this.data.inviteBusy) return
    wx.setClipboardData({
      data: this.data.inviteCode,
      success() {
        wx.showToast({ title: '邀请码已复制', icon: 'success' })
      },
    })
  },

  renameMe() {
    const that = this
    const mine = this.data.members.filter(function (row) {
      return row.isMe
    })[0]
    if (!mine) return
    wx.showModal({
      title: '你的称呼',
      editable: true,
      placeholderText: '别人在成员列表里看到的名字',
      content: mine.nickname || '',
      success(res) {
        if (!res.confirm) return
        const nick = String(res.content || '').trim()
        if (!nick) {
          wx.showToast({ title: '称呼不能为空', icon: 'none' })
          return
        }
        api
          .updateMember(mine.id, { nickname: nick })
          .then(function () {
            wx.showToast({ title: '已修改', icon: 'success' })
            that.load()
          })
          .catch(function (err) {
            wx.showModal({ title: '修改失败', content: api.friendly(err), showCancel: false })
          })
      },
    })
  },

  removeMember(event) {
    const that = this
    const id = Number(event.currentTarget.dataset.id)
    const target = this.data.members.filter(function (row) {
      return row.id === id
    })[0]
    if (!target) return
    wx.showModal({
      title: '把「' + target.displayName + '」移出？',
      content: '移出后对方就看不到这个厨房的私密内容，也接不了单了。之后可以凭邀请链接重新加入。',
      confirmColor: '#D64545',
      success(res) {
        if (!res.confirm) return
        api
          .removeMember(id)
          .then(function () {
            wx.showToast({ title: '已移出', icon: 'success' })
            that.load()
          })
          .catch(function (err) {
            wx.showModal({ title: '操作失败', content: api.friendly(err), showCancel: false })
          })
      },
    })
  },

  leaveKitchen() {
    const that = this
    if (!this.data.myMemberId) return
    wx.showModal({
      title: '退出这个厨房？',
      content: '退出后你不再是它的共有人，看不到订单和库存了。之后可以凭邀请链接重新加入。',
      confirmColor: '#D64545',
      success(res) {
        if (!res.confirm) return
        api
          .removeMember(that.data.myMemberId)
          .then(function () {
            recent.forgetIf(that.kitchenId)
            wx.showToast({ title: '已退出', icon: 'success' })
            setTimeout(function () {
              wx.switchTab({ url: '/pages/chef/chef' })
            }, 700)
          })
          .catch(function (err) {
            wx.showModal({ title: '退出失败', content: api.friendly(err), showCancel: false })
          })
      },
    })
  },

  goBack() {
    wx.navigateBack()
  },
})
