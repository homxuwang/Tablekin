const NAME_KEY = 'kitchen_diner_name'

// 点菜清单按厨房分开存：同一个人可能在好几个厨房点菜，混在一起会串单。
function cartKey(kitchenId) {
  return 'kitchen_cart_' + String(kitchenId || '0')
}

function safeRead(key, fallback) {
  try {
    const raw = wx.getStorageSync(key)
    return raw === '' || raw === undefined || raw === null ? fallback : raw
  } catch (err) {
    return fallback
  }
}

function readCart(kitchenId) {
  const raw = safeRead(cartKey(kitchenId), null)
  return raw && typeof raw === 'object' ? raw : {}
}

function writeCart(kitchenId, cart) {
  try {
    wx.setStorageSync(cartKey(kitchenId), cart || {})
  } catch (err) {
    // 写入失败不影响点菜主流程
  }
}

function toList(cart) {
  const source = cart || {}
  return Object.keys(source)
    .map(function (key) {
      return source[key]
    })
    .filter(function (item) {
      return item && item.count > 0
    })
}

function totalCount(cart) {
  return toList(cart).reduce(function (sum, item) {
    return sum + item.count
  }, 0)
}

// 点菜人的称呼：第一次填过就记住，下次自动带上。
function readDinerName() {
  return String(safeRead(NAME_KEY, '') || '')
}

function writeDinerName(name) {
  try {
    wx.setStorageSync(NAME_KEY, String(name || '').trim())
  } catch (err) {
    // 记不住也不影响下单
  }
}

function clear(kitchenId) {
  writeCart(kitchenId, {})
}

module.exports = {
  readCart: readCart,
  writeCart: writeCart,
  toList: toList,
  totalCount: totalCount,
  readDinerName: readDinerName,
  writeDinerName: writeDinerName,
  clear: clear,
}
