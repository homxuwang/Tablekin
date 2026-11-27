// 记住上一次打开的厨房：下次进小程序直接落到那个厨房的菜单，
// 不用每次都从厨房列表里重新找一遍。
const KEY = 'kitchen_last_id'

function readLastKitchen() {
  try {
    const id = Number(wx.getStorageSync(KEY) || 0)
    return id > 0 ? id : 0
  } catch (err) {
    return 0
  }
}

function writeLastKitchen(kitchenId) {
  const id = Number(kitchenId || 0)
  if (!id) return
  try {
    wx.setStorageSync(KEY, id)
  } catch (err) {
    // 记不住只是少一次便利，不影响点菜
  }
}

// 上次那个厨房进不去了（被删掉、被移出成员）时把这笔记忆清掉，避免每次进来都撞墙。
function clearLastKitchen() {
  try {
    wx.removeStorageSync(KEY)
  } catch (err) {
    // 忽略
  }
}

// 厨房被删掉 / 退出厨房时调用：只在这个厨房正好是「上次那个」时才清
function forgetIf(kitchenId) {
  const id = Number(kitchenId || 0)
  if (!id) return
  if (readLastKitchen() === id) clearLastKitchen()
}

module.exports = {
  readLastKitchen: readLastKitchen,
  writeLastKitchen: writeLastKitchen,
  clearLastKitchen: clearLastKitchen,
  forgetIf: forgetIf,
}
