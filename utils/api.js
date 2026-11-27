const { cloud } = require('./cloud')
const mealTime = require('./meal-time')
const dishImages = require('./dish-images')
const dishTags = require('./dish-tags')

let sessionPromise = null

function pickUser(payload) {
  if (!payload) return null
  return payload.user || payload
}

async function readSession() {
  try {
    const { data, error } = await cloud.auth.getSession()
    if (error) return null
    return pickUser(data)
  } catch (err) {
    return null
  }
}

function wechatLogin() {
  return new Promise((resolve, reject) => {
    wx.login({
      success(res) {
        const code = res && res.code
        if (!code) {
          reject(new Error('微信登录未取得凭证，请重试'))
          return
        }
        let appid = ''
        try {
          appid = wx.getAccountInfoSync().miniProgram.appId
        } catch (err) {
          appid = ''
        }
        cloud.auth
          .signInWithWechat(code, appid)
          .then(({ data, error }) => {
            if (error) {
              reject(new Error(error.message || '微信登录失败，请重试'))
              return
            }
            resolve(pickUser(data))
          })
          .catch(() => {
            reject(new Error('微信登录失败，请重试'))
          })
      },
      fail(res) {
        reject(new Error((res && res.errMsg) || '微信登录失败，请重试'))
      },
    })
  })
}

// 小程序内是静默登录：进入即自动取得身份，用户不需要点授权。
function ensureSession() {
  if (sessionPromise) return sessionPromise
  sessionPromise = (async () => {
    const existing = await readSession()
    if (existing) return existing
    const user = await wechatLogin()
    if (!user) throw new Error('未能取得登录身份，请重试')
    return user
  })().catch((err) => {
    sessionPromise = null
    throw err
  })
  return sessionPromise
}

async function requireUser() {
  const user = await ensureSession()
  if (!user || !user.id) throw new Error('登录状态不可用，请稍后重试')
  return user
}

function unwrap(result) {
  if (!result) throw new Error('服务没有响应，请检查网络')
  if (result.error) throw result.error
  return result.data
}

function asArray(value) {
  return Array.isArray(value) ? value : []
}

// 服务端 RPC 的业务校验统一抛这些错误码，前端只负责翻译，不做判定——
// 「能不能做」这件事只由数据库说了算。
const RPC_ERRORS = {
  sort_kind_invalid: '排序类型不正确，请重新进入',
  sort_items_invalid: '排序项目有变化，请刷新列表后重试',
  sort_conflict: '其他成员已调整顺序或增删项目，请刷新列表后重新排序',
  not_signed_in: '登录状态不可用，请重新进入小程序',
  kitchen_not_found: '这个厨房不存在了，回首页换一个吧',
  kitchen_not_visible: '这是个私密厨房，要进去得先请大厨把邀请码发给你',
  kitchen_name_required: '请先给厨房起个名字',
  kitchen_name_too_long: '厨房名字有点长，30 个字以内就好',
  order_items_required: '还没有点菜，先挑几道吧',
  order_too_many_items: '一次点得太多了，分两单发吧',
  shortage_too_many_items: '缺料提醒太多，请分批上报',
  order_item_invalid: '这一单里有认不出来的菜，回菜单重新选一下',
  dish_not_in_kitchen: '有道菜不属于这个厨房，回菜单重新选一下',
  quantity_invalid: '份数不太对，请重新填一下',
  order_not_found: '这一单找不到了，可能已经被撤回',
  not_kitchen_member: '你不是这个厨房的成员，做不了这个操作',
  order_not_pending: '这一单已经处理过了，刷新看看最新状态',
  order_already_accepted: '大厨已经接单了，这时候撤不了，跟大厨说一声吧',
  order_not_accepted: '这一单还没接单，不能标记出餐',
  order_not_cancelable: '这一单现在的状态不能撤回',
  diner_only: '只有点这一单的人才能撤回',
  meal_time_invalid: '就餐时间没填对，回结算页重新选一下',
  ingredient_missing: '这一单要用到的某个食材已经被删掉了，补一下再试',
  ingredient_not_in_kitchen: '这一单用到了别的厨房的食材，请检查菜谱配方',
  kitchen_not_owner: '只有厨房拥有者能做这个操作',
  not_kitchen_owner: '只有厨房拥有者能做这个操作',
  ingredient_not_found: '这份食材不存在或已删除，请刷新库存',
  order_date_past: '就餐日期不能早于今天，回结算页重新选一个',
  order_date_invalid: '请选择有效的就餐日期，最多可预约未来365天',
  asap_requires_today: '「尽快」只能用在今天；预约其他日期请选个时间',
  value_invalid: '数量填得不对，请输入有效数字',
  mode_invalid: '库存操作类型不对，请重试',
  expected_stock_required: '盘点前请先看到当前库存',
  no_change: '库存没有变化',
  stock_negative: '库存不能为负数',
  stock_too_large: '数量太大了，分几次记吧',
  request_id_reused: '这次操作编号已经用过，请重新发起',
  invite_code_conflict: '邀请码生成冲突，请再试一次',
}

function friendly(error) {
  const message = (error && (error.message || error.details)) || ''
  const raw = String(message).split('\n')[0].trim()
  const parts = raw.split(':')
  const head = parts[0]

  // 带明细的两类错误：把服务端算出来的数字直接讲给用户听
  if (head === 'ingredient_shortage') {
    return (
      '「' +
      (parts[1] || '某种食材') +
      '」不够：要 ' +
      (parts[3] || '?') +
      '，只剩 ' +
      (parts[2] || '0') +
      '。先去食材管理补一下库存。'
    )
  }
  if (head === 'dish_not_orderable') {
    const name = parts.slice(1).join(':')
    return name ? '「' + name + '」今天点不了，换一道试试' : '这道菜今天点不了'
  }
  // 盘点时拿的是旧页面数据：把「现在实际有多少」讲清楚，让用户刷新后再来
  if (head === 'stock_changed') {
    return (
      '这份库存刚被别的操作改过：现在实际是 ' +
      (parts[1] || '?') +
      '，你页面上看到的是 ' +
      (parts[2] || '?') +
      '。刷新一下再盘点。'
    )
  }
  if (RPC_ERRORS[head]) return RPC_ERRORS[head]

  if (head === 'image_empty') return '这张图片读不出来，换一张试试'
  if (head === 'image_too_large') return '图片太大了（单张上限 10MB），换一张小一点的'
  // 上传通道没挂上时 SDK 会抛这句，说明补丁没生效而不是用户的操作有问题
  if (/暂不支持非字符串/.test(raw)) return '图片上传通道没接上，请更新小程序后重试'
  if (/wx\.request failed|request:fail/i.test(raw)) {
    return /timeout/i.test(raw) ? '网络超时，图片没传上去，请重试' : '网络不给力，图片没传上去，请重试'
  }
  if (/invite_code_not_found/i.test(raw)) return '邀请码无效或已失效，请向邀请你的人要一个新的链接'
  if (/access_denied|未授权给/i.test(raw)) {
    return '小程序还没有授权给 WorkBuddy，请先在分享面板里完成小程序绑定'
  }
  // 服务端 CHECK 挡下来的非法多图/标签：说清楚到底是哪一条不合要求
  if (error && error.code === '23514') {
    if (/dishes_tags_valid/.test(raw)) return '标签不合规：每道菜最多 12 个，单个 12 字以内，且不能有逗号、引号或多余空格'
    if (/dishes_image_paths/.test(raw)) return '图片列表不合法，请重新选择图片'
    return '内容不符合要求，请检查后重试'
  }
  if (error && error.code === '23505') return '已经有同名的记录了，请换一个名字'
  if (error && error.code === '42501') return '没有权限执行该操作'
  if (error && error.code === '42P01') return '数据表尚未创建，请稍后重试'
  if (/url not in domain list/i.test(raw)) return '网络请求被微信拦截，请检查服务器域名配置'
  return raw || '操作失败，请稍后重试'
}

const todayString = mealTime.todayString

function round1(value) {
  return Math.round(Number(value || 0) * 10) / 10
}

// ---------- 厨房 ----------

// 我参与的全部厨房（自己创建的 + 被邀请加入的）
async function fetchMyKitchens() {
  const user = await requireUser()
  const rows = asArray(
    unwrap(
      await cloud.database
        .from('kitchen_members')
        .select(
          'id, role, nickname, kitchen_id, kitchen:kitchens(id, name, description, cover_path, is_public, owner_id, created_at)'
        )
        .eq('user_id', user.id)
        .order('id', { ascending: true })
    )
  )
  return rows
    .map(function (row) {
      const kitchen = row.kitchen
      if (!kitchen || !kitchen.id) return null
      return Object.assign({}, kitchen, {
        memberId: row.id,
        role: row.role || 'member',
        myNickname: row.nickname || '',
        isOwner: row.role === 'owner' || kitchen.owner_id === user.id,
      })
    })
    .filter(function (item) {
      return !!item
    })
}

async function fetchKitchen(kitchenId) {
  await requireUser()
  const row = unwrap(
    await cloud.database.from('kitchens').select('*').eq('id', kitchenId).maybeSingle()
  )
  return row || null
}

// 一次把若干个厨房查出来（搜索结果里补厨房名用）
async function fetchKitchensByIds(ids) {
  const list = asArray(ids).filter(function (id) {
    return !!id
  })
  if (!list.length) return []
  await requireUser()
  const rows = unwrap(await cloud.database.from('kitchens').select('*').in('id', list))
  return asArray(rows)
}

// keyword 为空时返回公开厨房（用于「发现」），有值时按名称模糊搜索
async function searchKitchens(keyword) {
  await requireUser()
  const kw = String(keyword || '').trim()
  let query = cloud.database.from('kitchens').select('*')
  if (kw) {
    query = query.ilike('name', '%' + kw + '%')
  } else {
    query = query.eq('is_public', true)
  }
  const rows = unwrap(await query.order('created_at', { ascending: false }).limit(30))
  return asArray(rows)
}

// 建厨房 = 写厨房 + 写拥有者成员行，两件事在数据库端同一个事务里完成：
// 要么都成，要么都不成，不会留下「建了厨房却没人管」的半截数据。
// 拥有者身份由登录会话决定，前端不传也不用传。
async function createKitchen(payload) {
  await requireUser()
  const name = String((payload && payload.name) || '').trim()
  if (!name) throw new Error('请先给厨房起个名字')
  const data = unwrap(
    await cloud.database.rpc('create_kitchen_atomic', {
      p_name: name,
      p_description: String((payload && payload.description) || '').trim() || null,
      p_is_public: payload && payload.is_public === undefined ? true : !!payload.is_public,
      p_cover_path: String((payload && payload.cover_path) || '').trim() || null,
      p_nickname: String((payload && payload.nickname) || '').trim() || null,
    })
  )
  if (!data || !data.kitchen_id) throw new Error('厨房创建失败，请重试')
  // 整理成和 kitchens 行一样的形状，页面只认 id / name / invite_code 这几个字段
  return Object.assign({}, data, { id: data.kitchen_id })
}

// 邀请码单独存在一张只有拥有者能读的表里，必须走这个接口取，且只有拥有者取得到。
// 普通厨房查询（包括 select('*')）不会再带回任何可用于入伙的凭证。
async function getKitchenInvite(kitchenId) {
  await requireUser()
  const data = unwrap(
    await cloud.database.rpc('get_kitchen_invite', { p_kitchen_id: Number(kitchenId) })
  )
  return data
}

// 重置邀请码 = 之前发出去的链接和码立刻失效（移出成员后想收回邀请就用它）。
// 微信分享卡片本身无法禁止被转发，只能靠换码来控制「谁还能进来」。
async function resetKitchenInvite(kitchenId) {
  await requireUser()
  const data = unwrap(
    await cloud.database.rpc('reset_kitchen_invite', { p_kitchen_id: Number(kitchenId) })
  )
  return data
}

async function updateKitchen(kitchenId, payload) {
  await requireUser()
  const rows = asArray(
    unwrap(await cloud.database.from('kitchens').update(payload).eq('id', kitchenId).select())
  )
  if (rows.length === 0) throw new Error('没有厨房被修改，可能你没有管理权限')
  return rows[0]
}

async function deleteKitchen(kitchenId) {
  await requireUser()
  const rows = asArray(
    unwrap(await cloud.database.from('kitchens').delete().eq('id', kitchenId).select())
  )
  if (rows.length === 0) throw new Error('厨房没有删除成功，可能你不是它的拥有者')
  return true
}

// ---------- 厨房成员 ----------

async function fetchMembers(kitchenId) {
  await requireUser()
  const rows = unwrap(
    await cloud.database
      .from('kitchen_members')
      .select('*')
      .eq('kitchen_id', kitchenId)
      .order('id', { ascending: true })
  )
  return asArray(rows)
}

// 凭邀请码入伙：校验与写入都在数据库端完成，前端拿不到也不该拿到「谁能进来」的判定权。
async function joinKitchenByCode(code, nickname) {
  await requireUser()
  const data = unwrap(
    await cloud.database.rpc('join_kitchen_by_code', {
      code: String(code || '').trim(),
      nick: String(nickname || '').trim(),
    })
  )
  return data
}

async function updateMember(memberId, payload) {
  await requireUser()
  const rows = asArray(
    unwrap(
      await cloud.database.from('kitchen_members').update(payload).eq('id', memberId).select()
    )
  )
  if (rows.length === 0) throw new Error('没有成员被修改，可能你没有这个权限')
  return rows[0]
}

// 移出成员 / 自己退出：拥有者可以移出任何人，成员只能移出自己
async function removeMember(memberId) {
  await requireUser()
  const rows = asArray(
    unwrap(await cloud.database.from('kitchen_members').delete().eq('id', memberId).select())
  )
  if (rows.length === 0) throw new Error('没有成员被移出，可能你没有这个权限')
  return true
}

// ---------- 分类 ----------

function reorderRpcUnavailable(error) {
  if (!error) return false
  if (['PGRST202', '42883'].includes(String(error.code))) return true
  const message = typeof error === 'string' ? error : String(error.message || error.details || '')
  return /reorder_kitchen_items/i.test(message) && /schema cache|could not find.*function|does not exist/i.test(message)
}

async function reorderKitchenItems(kitchenId, kind, ids, expectedIds) {
  const validIds = list => Array.isArray(list) && list.length > 0 &&
    list.every(id => Number.isSafeInteger(Number(id)) && Number(id) > 0) &&
    new Set(list.map(String)).size === list.length
  if (!Number.isSafeInteger(Number(kitchenId)) || Number(kitchenId) <= 0 ||
      !['categories', 'dishes'].includes(kind) || !validIds(ids) || !validIds(expectedIds) ||
      ids.length !== expectedIds.length || !ids.every(id => expectedIds.some(before => String(before) === String(id)))) {
    throw new Error('排序参数无效，请刷新列表后重试')
  }
  await requireUser()
  try {
    const result = await cloud.database.rpc('reorder_kitchen_items', {
      p_kitchen_id: Number(kitchenId), p_kind: kind,
      p_ids: ids.map(Number), p_expected_ids: expectedIds.map(Number),
    })
    return unwrap(result)
  } catch (err) {
    if (reorderRpcUnavailable(err)) throw new Error('排序服务尚未上线，请联系管理员更新后重试')
    throw err
  }
}

async function fetchCategories(options) {
  const opts = options || {}
  await requireUser()
  let query = cloud.database.from('categories').select('*')
  if (opts.kitchenId) query = query.eq('kitchen_id', opts.kitchenId)
  if (opts.publicOnly) query = query.eq('is_public', true)
  const rows = unwrap(
    await query.order('sort_order', { ascending: true }).order('id', { ascending: true })
  )
  return asArray(rows)
}

async function createCategory(payload) {
  await requireUser()
  const rows = unwrap(await cloud.database.from('categories').insert(payload).select())
  const created = asArray(rows)[0]
  if (!created) throw new Error('分类创建失败，请重试')
  return created
}

async function updateCategory(id, payload) {
  await requireUser()
  const rows = unwrap(await cloud.database.from('categories').update(payload).eq('id', id).select())
  const affected = asArray(rows)
  if (affected.length === 0) throw new Error('没有分类被修改，它可能不属于这个厨房')
  return affected[0]
}

async function deleteCategory(id) {
  await requireUser()
  const rows = unwrap(await cloud.database.from('categories').delete().eq('id', id).select())
  if (asArray(rows).length === 0) throw new Error('没有分类被删除，它可能不属于这个厨房')
  return true
}

// ---------- 菜品 ----------

async function fetchDishes(options) {
  const opts = options || {}
  await requireUser()
  let query = cloud.database.from('dishes').select('*')
  const kitchenIds = asArray(opts.kitchenIds).filter(function (id) {
    return !!id
  })
  if (kitchenIds.length) query = query.in('kitchen_id', kitchenIds)
  else if (opts.kitchenId) query = query.eq('kitchen_id', opts.kitchenId)
  if (opts.publicOnly) query = query.eq('is_public', true)
  if (opts.categoryId) query = query.eq('category_id', opts.categoryId)
  query = applyTagFilter(query, opts.tags, opts.tagMode)
  const rows = unwrap(
    await query.order('sort_order', { ascending: true }).order('id', { ascending: true })
  )
  return asArray(rows)
}

// 多标签筛选：'all'（默认）要同时带上所有标签，'any' 命中任意一个即可。
// 走的是 PostgreSQL 的 @> / &&，由 dishes_tags_gin 索引加速。
function applyTagFilter(query, tags, mode) {
  const names = dishTags.clean(tags)
  if (!names.length) return query
  return mode === 'any' ? query.overlaps('tags', names) : query.contains('tags', names)
}

// 标签云：编辑菜品时用来挑已有标签复用，搜索页拿来当筛选项。
// kitchenId 传 0 表示「我能看到的所有厨房」。
async function listKitchenTags(kitchenId, limit) {
  await requireUser()
  const data = unwrap(
    await cloud.database.rpc('list_kitchen_tags', {
      p_kitchen_id: Number(kitchenId || 0),
      p_limit: Number(limit || 60),
    })
  )
  const row = asArray(data)[0] || data || {}
  return asArray(row.tags).map(function (item) {
    return {
      name: dishTags.normalize(item && item.tag),
      count: Number((item && item.dish_count) || 0),
    }
  })
}

// 顾客首页用：一次数出这些厨房各有几道在售的菜，避免一个厨房发一次请求
async function countPublicDishes(kitchenIds) {
  const ids = asArray(kitchenIds).filter(function (id) {
    return !!id
  })
  if (!ids.length) return {}
  const rows = await fetchDishes({ kitchenIds: ids, publicOnly: true })
  const result = {}
  ids.forEach(function (id) {
    result[id] = 0
  })
  rows.forEach(function (dish) {
    if (result[dish.kitchen_id] === undefined) return
    if (dish.is_available === false) return
    result[dish.kitchen_id] += 1
  })
  return result
}

async function fetchDish(id) {
  await requireUser()
  const row = unwrap(await cloud.database.from('dishes').select('*').eq('id', id).maybeSingle())
  return row || null
}

// 按菜名和/或标签搜菜。带 kitchenId 就在一个厨房里搜（首页放大镜的「本厨房」），
// 不带就搜「我能看到的全部厨房」——库里能返回哪些由 RLS 决定，前端不做过滤。
// 菜名和标签可以同时给，也可以只给一个；两个都不给就没有结果。
async function searchDishes(options) {
  const opts = options || {}
  await requireUser()
  const kw = String(opts.keyword || '').trim()
  const names = dishTags.clean(opts.tags)
  if (!kw && !names.length) return []
  let query = cloud.database.from('dishes').select('*')
  if (kw) query = query.ilike('name', '%' + kw + '%')
  if (opts.kitchenId) query = query.eq('kitchen_id', opts.kitchenId)
  query = applyTagFilter(query, names, opts.tagMode)
  const rows = unwrap(await query.order('id', { ascending: true }).limit(60))
  return asArray(rows)
}

// 写入前把图片和标签各归一次位：图片保证首图与数组第一项一致，
// 标签保证去重、掐空白、不超上限。服务端 CHECK 是第二道关。
function dishSavePayload(payload) {
  const input = dishImagePayload(payload)
  if (Object.prototype.hasOwnProperty.call(input, 'tags')) {
    Object.assign(input, dishTags.fields(input.tags))
  }
  return input
}

async function createDish(payload) {
  await requireUser()
  const input = dishSavePayload(payload)
  const rows = unwrap(await cloud.database.from('dishes').insert(input).select())
  const created = asArray(rows)[0]
  if (!created) throw new Error('菜品保存失败，请重试')
  return created
}

async function updateDish(id, payload) {
  await requireUser()
  const input = dishSavePayload(payload)
  const rows = unwrap(await cloud.database.from('dishes').update(input).eq('id', id).select())
  const affected = asArray(rows)
  if (affected.length === 0) throw new Error('没有菜品被修改，它可能不属于这个厨房')
  return affected[0]
}

async function deleteDish(id) {
  await requireUser()
  const rows = unwrap(await cloud.database.from('dishes').delete().eq('id', id).select())
  if (asArray(rows).length === 0) throw new Error('没有菜品被删除，它可能不属于这个厨房')
  return true
}

// ---------- 菜品图片 ----------

function dishImagePayload(payload) {
  const input = Object.assign({}, payload)
  if (Object.prototype.hasOwnProperty.call(input, 'image_paths') || Object.prototype.hasOwnProperty.call(input, 'image_path')) {
    Object.assign(input, dishImages.fields(dishImages.paths(input)))
  }
  return input
}

const EXT_BY_TYPE = {
  'image/png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif',
  'image/jpeg': 'jpg',
}

function guessContentType(filePath) {
  const lower = String(filePath || '').toLowerCase()
  if (lower.indexOf('.png') >= 0) return 'image/png'
  if (lower.indexOf('.webp') >= 0) return 'image/webp'
  if (lower.indexOf('.gif') >= 0) return 'image/gif'
  return 'image/jpeg'
}

// 单张图片上限：再大就容易在弱网下超时，且菜图也没必要用原图。
const MAX_IMAGE_BYTES = 10 * 1024 * 1024

async function uploadDishImage(tempFilePath) {
  const user = await requireUser()
  const contentType = guessContentType(tempFilePath)
  const extension = EXT_BY_TYPE[contentType] || 'jpg'
  const buffer = wx.getFileSystemManager().readFileSync(tempFilePath)
  if (!buffer || !buffer.byteLength) {
    const empty = new Error('image_empty')
    throw empty
  }
  if (buffer.byteLength > MAX_IMAGE_BYTES) {
    const large = new Error('image_too_large')
    throw large
  }
  const target = cloud.storage.sharedPath(
    user.id,
    'dishes/' + Date.now() + '-' + Math.floor(Math.random() * 100000) + '.' + extension
  )
  const result = await cloud.storage.upload(target, buffer, { contentType: contentType })
  if (result && result.error) {
    const failure = new Error((result.error && result.error.message) || '图片上传失败')
    // SDK 的网络错误没有 HTTP code，带上名字便于前端给出具体提示
    failure.code = (result.error && result.error.code) || (result.error && result.error.name) || ''
    throw failure
  }
  return target
}

// 图片读取走签名地址，失败时静默返回空表，页面会退回文字占位。
async function signImageUrls(paths) {
  const list = []
  const seen = {}
  ;(paths || []).forEach((path) => {
    if (path && !seen[path]) {
      seen[path] = true
      list.push(path)
    }
  })
  if (list.length === 0) return {}
  try {
    const result = await cloud.storage.createSignedUrls(list, 3600)
    if (result && result.error) return {}
    const map = {}
    asArray(result && result.data).forEach((item) => {
      if (!item) return
      const path = item.path || item.name
      const url = item.signedUrl || item.signedURL || item.url
      if (path && url) map[path] = url
    })
    return map
  } catch (err) {
    return {}
  }
}

// ---------- 食材仓库 ----------

async function fetchIngredients(options) {
  const opts = options || {}
  await requireUser()
  let query = cloud.database.from('ingredients').select('*')
  if (opts.kitchenId) query = query.eq('kitchen_id', opts.kitchenId)
  const rows = unwrap(
    await query.order('sort_order', { ascending: true }).order('id', { ascending: true })
  )
  return asArray(rows)
}

async function createIngredient(payload) {
  await requireUser()
  const input = Object.assign({}, payload || {})
  const initial = Number(input.stock || 0)
  if (!Number.isFinite(initial) || initial < 0) throw new Error('初始库存须为不小于0的有效数字')
  // 客户端已经没有写 stock 的权限：新建一律先落 0，再走一次盘点事务把初始库存记上
  delete input.stock
  const rows = unwrap(await cloud.database.from('ingredients').insert(input).select())
  const created = asArray(rows)[0]
  if (!created) throw new Error('食材保存失败，请重试')
  if (initial > 0) {
    try {
      const result = await adjustStock({
      ingredientId: created.id,
      mode: 'recount',
      value: initial,
      expectedStock: 0,
      reason: '新建食材初始库存',
        requestId: 'initial-' + created.id,
      })
      created.stock = result.balance
    } catch (error) {
      const failure = new Error('食材已创建，但初始库存结果未确认。请刷新后核对库存，避免重复创建。')
      failure.ingredient = created
      failure.initialStock = initial
      failure.cause = error
      throw failure
    }
  }
  return created
}

async function updateIngredient(id, payload) {
  await requireUser()
  const rows = unwrap(await cloud.database.from('ingredients').update(payload).eq('id', id).select())
  const affected = asArray(rows)
  if (affected.length === 0) throw new Error('没有食材被修改，它可能不属于这个厨房')
  return affected[0]
}

async function deleteIngredient(id) {
  await requireUser()
  const rows = unwrap(await cloud.database.from('ingredients').delete().eq('id', id).select())
  if (asArray(rows).length === 0) throw new Error('没有食材被删除，它可能不属于这个厨房')
  return true
}

// 库存变动只有这一条路：服务端在食材行锁内一次完成「改库存 + 写流水」。
// 前端不再「先读 stock 再回写绝对值」——那会覆盖大厨同时接单扣掉的库存。
//   mode='delta'   入库：在当前库存上加 value，不需要 expectedStock
//   mode='recount' 盘点：value 是实际绝对值，必须带盘点前页面看到的 expectedStock；
//                  服务端会在锁内核对，不一致就抛 stock_changed 让用户刷新，
//                  绝不用陈旧页面上的数字覆盖接单扣库。
// requestId 可选：响应丢失后重试时用它去重，同一次操作只会生效一次。
async function adjustStock(options) {
  const opts = options || {}
  await requireUser()
  const ingredientId = Number(opts.ingredientId || 0)
  if (!ingredientId) throw new Error('没能识别要改哪样食材')
  const mode = opts.mode || 'delta'
  if (mode !== 'delta' && mode !== 'recount') throw new Error('库存操作类型不对，请重试')
  const value = Number(opts.value)
  if (opts.value === undefined || opts.value === null || opts.value === '' || !Number.isFinite(value) || value < 0 || (mode === 'delta' && value === 0)) {
    throw new Error('请输入有效库存数量，入库须大于0，盘点不能小于0')
  }
  if (mode === 'recount' && (opts.expectedStock === undefined || opts.expectedStock === null || opts.expectedStock === '' || !Number.isFinite(Number(opts.expectedStock)))) {
    throw new Error('盘点前请先看到当前库存')
  }
  const data = unwrap(
    await cloud.database.rpc('adjust_stock_atomic', {
      p_ingredient_id: ingredientId,
      p_mode: mode,
      p_value: value,
      p_reason: String(opts.reason || '').trim() || null,
      p_expected_stock: mode === 'recount' ? Number(opts.expectedStock) : null,
      p_request_id: String(opts.requestId || '').trim() || null,
    })
  )
  if (!data || !data.ok) throw new Error('库存没有更新成功，请重试')
  return {
    ingredientId: Number(data.ingredient_id),
    balance: Number(data.balance || 0),
    change: Number(data.change || 0),
    replayed: !!data.replayed,
  }
}

async function fetchStockLogs(ingredientId) {
  await requireUser()
  const rows = unwrap(
    await cloud.database
      .from('stock_logs')
      .select('*')
      .eq('ingredient_id', ingredientId)
      .order('created_at', { ascending: false })
      .limit(50)
  )
  return asArray(rows)
}

// ---------- 菜品用料（配方） ----------

async function fetchRecipes(options) {
  const opts = options || {}
  await requireUser()
  let query = cloud.database.from('dish_ingredients').select('*')
  if (opts.dishId) query = query.eq('dish_id', opts.dishId)
  else if (opts.kitchenId) query = query.eq('kitchen_id', opts.kitchenId)
  const rows = unwrap(await query.order('id', { ascending: true }))
  return asArray(rows)
}

async function replaceDishIngredients(dishId, kitchenId, list) {
  await requireUser()
  unwrap(await cloud.database.from('dish_ingredients').delete().eq('dish_id', dishId).select())
  const rows = (list || [])
    .filter(function (item) {
      return item && item.ingredient_id && Number(item.amount) > 0
    })
    .map(function (item) {
      return {
        dish_id: dishId,
        kitchen_id: kitchenId,
        ingredient_id: Number(item.ingredient_id),
        amount: Number(item.amount),
      }
    })
  if (rows.length) {
    unwrap(await cloud.database.from('dish_ingredients').insert(rows))
  }
  return true
}

// ---------- 可做份数计算（本地） ----------

// 返回 { [dishId]: { hasRecipe, canMake: number|null, lacks: [] } }
// canMake 为 null 表示这道菜没有约束（没配用料）
function buildAvailability(dishes, ingredients, recipes) {
  const stockById = {}
  asArray(ingredients).forEach(function (item) {
    stockById[item.id] = item
  })
  const byDish = {}
  asArray(recipes).forEach(function (row) {
    if (row.dish_id === null || row.dish_id === undefined) return
    if (!byDish[row.dish_id]) byDish[row.dish_id] = []
    byDish[row.dish_id].push(row)
  })
  const result = {}
  asArray(dishes).forEach(function (dish) {
    const rows = byDish[dish.id] || []
    let canMake = null
    const lacks = []
    rows.forEach(function (row) {
      const ingredient = stockById[row.ingredient_id]
      const amount = Number(row.amount || 0)
      if (!ingredient || amount <= 0) return
      const possible = Math.floor(Number(ingredient.stock || 0) / amount)
      canMake = canMake === null ? possible : Math.min(canMake, possible)
      if (possible <= 0) {
        lacks.push({
          ingredientId: ingredient.id,
          ingredientName: ingredient.name,
          unit: ingredient.unit,
          amount: amount,
          stock: Number(ingredient.stock || 0),
        })
      }
    })
    result[dish.id] = {
      hasRecipe: rows.length > 0,
      canMake: canMake,
      lacks: lacks,
      text: canMake === null ? '' : canMake > 0 ? '还能做 ' + canMake + ' 份' : '食材不足',
    }
  })
  return result
}

// wanted: { dishId: 份数 } —— 判断这一单所需的食材够不够
function checkOrderAvailability(dishes, ingredients, recipes, wanted) {
  const ingredientById = {}
  asArray(ingredients).forEach(function (item) {
    ingredientById[item.id] = item
  })
  const dishById = {}
  asArray(dishes).forEach(function (dish) {
    dishById[dish.id] = dish
  })
  const needed = {}
  const dishNames = {}
  asArray(recipes).forEach(function (row) {
    const count = Number((wanted || {})[row.dish_id] || 0)
    const amount = Number(row.amount || 0)
    if (count <= 0 || amount <= 0) return
    needed[row.ingredient_id] = (needed[row.ingredient_id] || 0) + amount * count
    if (!dishNames[row.ingredient_id]) dishNames[row.ingredient_id] = []
    const dish = dishById[row.dish_id]
    const name = dish ? dish.name : ''
    if (name && dishNames[row.ingredient_id].indexOf(name) < 0) {
      dishNames[row.ingredient_id].push(name)
    }
  })
  const problems = []
  Object.keys(needed).forEach(function (key) {
    const ingredient = ingredientById[key]
    if (!ingredient) return
    const need = round1(needed[key])
    const stock = Number(ingredient.stock || 0)
    if (need > stock) {
      problems.push({
        ingredientId: ingredient.id,
        ingredientName: ingredient.name,
        unit: ingredient.unit,
        needed: need,
        stock: stock,
        short: round1(need - stock),
        dishes: (dishNames[key] || []).join('、'),
      })
    }
  })
  return { ok: problems.length === 0, problems: problems }
}

// ---------- 今日点餐 ----------

// 就餐时间有三种：尽快、定一个点（18:30）、定一个范围（18:00 之后 / 18:00–19:00）
const normalizeMealTime = mealTime.normalizeMealTime
const mealTimeText = mealTime.mealTimeText
const mealScheduleText = mealTime.mealScheduleText

// 顾客看到的五种状态；「大厨已收到」是 pending + 已回执，单独算一种
const ORDER_STATUS = {
  pending: { text: '等大厨回复', tone: 'wait' },
  accepted: { text: '大厨正在做', tone: 'doing' },
  done: { text: '已出餐', tone: 'done' },
  rejected: { text: '这单没做成', tone: 'off' },
  cancelled: { text: '已撤回', tone: 'off' },
}

function orderStatus(order) {
  if (!order) return { key: 'pending', text: '', tone: 'wait' }
  if (order.status === 'pending' && order.acked_at) {
    return { key: 'acked', text: '大厨已收到', tone: 'ack' }
  }
  const found = ORDER_STATUS[order.status]
  if (found) return { key: order.status, text: found.text, tone: found.tone }
  return { key: order.status || '', text: order.status || '', tone: 'wait' }
}

// 订单进度：已发送 → 大厨已收到 → 正在做 → 已出餐；撤回的单只有两格。
function orderSteps(order) {
  const status = (order && order.status) || 'pending'
  if (status === 'cancelled') {
    return [
      { key: 'sent', label: '已发送给大厨', at: (order && order.created_at) || '', done: true },
      { key: 'cancelled', label: '点菜人已撤回', at: (order && order.cancelled_at) || '', done: true },
    ]
  }
  if (status === 'rejected') {
    const steps = [{ key: 'sent', label: '已发送给大厨', at: order.created_at || '', done: true }]
    if (order.acked_at) steps.push({ key: 'acked', label: '大厨已收到', at: order.acked_at, done: true })
    steps.push({ key: 'rejected', label: '大厨回复做不了', at: order.decided_at || '', done: true })
    return steps
  }
  const accepted = status === 'accepted' || status === 'done'
  return [
    { key: 'sent', label: '已发送给大厨', at: (order && order.created_at) || '', done: true },
    { key: 'acked', label: '大厨已收到', at: (order && order.acked_at) || '', done: !!order.acked_at || accepted },
    { key: 'accepted', label: '大厨接单，开始做', at: (order && order.decided_at) || '', done: accepted },
    { key: 'done', label: '已出餐', at: (order && order.done_at) || '', done: status === 'done' },
  ]
}

// 下单是一个服务端事务：核对厨房可访问、每道菜确实属于这个厨房且今天可点、份数为正，
// 然后把订单和全部明细一次写完。任何一步不过就整单回滚，不会留下只有单头没有菜的空订单。
// 点菜人身份取自登录会话；菜品名也以库里为准，不接受前端传什么就存什么。
async function createOrder(payload) {
  await requireUser()
  const items = asArray(payload && payload.items)
  if (!items.length) throw new Error('还没有点菜')
  const kitchenId = payload && payload.kitchenId
  if (!kitchenId) throw new Error('没能识别这份菜单属于哪个厨房，请回到菜单页重试')
  const meal = mealTime.validateSchedule(payload)
  const data = unwrap(
    await cloud.database.rpc('create_order_atomic', {
      p_kitchen_id: Number(kitchenId),
      p_items: items.map(function (item) {
        return {
          dish_id: Number(item.dish_id || item.id || 0),
          quantity: Number(item.quantity || item.count || 1),
        }
      }),
      p_note: String((payload && payload.note) || '').trim() || null,
      p_diner_name: String((payload && payload.dinerName) || '').trim() || null,
      p_meal_time_type: meal.meal_time_type,
      p_meal_time_start: meal.meal_time_start,
      p_meal_time_end: meal.meal_time_end,
      p_order_date: meal.order_date,
    })
  )
  if (!data || !data.order_id) throw new Error('这一单没有提交成功，请重试')
  return Object.assign({}, data, { id: data.order_id })
}

// 通用取单：按点菜人（我点的）、按厨房（一个或多个，我收到的）、按日期筛选，
// 都不传就返回「RLS 允许我看到的全部单」，订单 tab 就是这么用的。
async function fetchOrders(options) {
  const opts = options || {}
  const user = await requireUser()
  let query = cloud.database.from('orders').select('*')
  if (opts.onlyMine || opts.dinerId) query = query.eq('diner_id', opts.dinerId || user.id)
  const kitchenIds = asArray(opts.kitchenIds).filter(function (id) {
    return !!id
  })
  if (kitchenIds.length) query = query.in('kitchen_id', kitchenIds)
  else if (opts.kitchenId) query = query.eq('kitchen_id', opts.kitchenId)
  if (opts.date) query = query.eq('order_date', opts.date)
  if (opts.status) query = query.eq('status', opts.status)
  const rows = unwrap(await query.order('created_at', { ascending: false }).limit(opts.limit || 100))
  return asArray(rows)
}

// 我作为顾客点出去的单（跨厨房）
function fetchMyOrders(options) {
  const opts = options || {}
  return fetchOrders({
    onlyMine: true,
    kitchenId: opts.kitchenId || 0,
    date: opts.date || '',
    limit: opts.limit || 60,
  })
}

// 我作为大厨收到的单（跨我参与的全部厨房）
function fetchReceivedOrders(kitchenIds, options) {
  const opts = options || {}
  return fetchOrders({ kitchenIds: kitchenIds, date: opts.date || '', limit: opts.limit || 60 })
}

async function fetchOrder(orderId) {
  await requireUser()
  const row = unwrap(await cloud.database.from('orders').select('*').eq('id', orderId).maybeSingle())
  return row || null
}

// 大厨点「收到」：只写回执，不碰库存。重复点不会报错，也不会覆盖第一次的时间。
async function ackOrder(orderId) {
  await requireUser()
  const data = unwrap(
    await cloud.database.rpc('ack_order_atomic', { p_order_id: Number(orderId) })
  )
  if (!data || !data.ok) throw new Error('回执失败，你可能不是这个厨房的成员')
  return data
}

async function fetchOrderItems(orderIds) {
  const ids = asArray(orderIds).filter(function (id) {
    return !!id
  })
  if (!ids.length) return []
  await requireUser()
  const rows = unwrap(
    await cloud.database.from('order_items').select('*').in('order_id', ids).order('id', { ascending: true })
  )
  return asArray(rows)
}

// 接单是一个服务端事务：先锁住订单确认它还是「待处理」，再按固定顺序锁住要用到的每样食材，
// 核对全部用量后，一次扣库存、写库存流水、把状态改成已接单。
// 因此连着点两次也只会扣一次库存；任何一步不够，整笔回滚，
// 不会出现「库存扣了但单没接上」这种要么丢货要么丢单的状态。
// 没设配方的菜品不占库存，照常可以接单。
async function acceptOrder(orderId) {
  await requireUser()
  try {
    const data = unwrap(
      await cloud.database.rpc('accept_order_atomic', { p_order_id: Number(orderId) })
    )
    if (!data || !data.ok) throw new Error('接单失败，你可能不是这个厨房的成员')
    return {
      ok: true,
      order: Object.assign({}, data, { id: data.order_id }),
      deducted: asArray(data.deducted),
    }
  } catch (err) {
    const raw = String((err && (err.message || err.details)) || '')
    // 「够不够」由服务端在锁内判定，这里只把明细翻译成页面已有的提示格式
    if (raw.indexOf('ingredient_shortage') === 0) {
      const detail = raw.split('\n')[0].split(':')
      const stock = Number(detail[2] || 0)
      const needed = Number(detail[3] || 0)
      return {
        ok: false,
        problems: [
          {
            ingredientName: detail[1] || '某种食材',
            unit: '',
            needed: needed,
            stock: stock,
            short: round1(needed - stock),
            dishes: '',
          },
        ],
      }
    }
    throw err
  }
}

// 出餐：只有已经接单的单能走到这一步；重复点不会报错。
async function finishOrder(orderId) {
  await requireUser()
  const data = unwrap(
    await cloud.database.rpc('finish_order_atomic', { p_order_id: Number(orderId) })
  )
  if (!data || !data.ok) throw new Error('操作失败，你可能不是这个厨房的成员')
  return data
}

// 拒单：只允许还没接单的单。已接单的不能从这里回退——
// 那种情况该先把这单做完，或者另行调整库存，避免「库存扣了、单也没了」。
async function rejectOrder(orderId, reason) {
  await requireUser()
  const data = unwrap(
    await cloud.database.rpc('reject_order_atomic', {
      p_order_id: Number(orderId),
      p_reason: String(reason || '').trim() || null,
    })
  )
  if (!data || !data.ok) throw new Error('操作失败，你可能不是这个厨房的成员')
  return data
}

// 顾客撤单：只有点这一单的人、且订单还在「待处理」时能撤。
// 撤单是打标记（status = cancelled）而不是删行，厨房侧能看到「这单被撤了」，
// 已接单的单不能撤——那时候菜可能已经下锅，得跟大厨说一声。
async function cancelOrder(orderId) {
  await requireUser()
  const data = unwrap(
    await cloud.database.rpc('cancel_order_atomic', { p_order_id: Number(orderId) })
  )
  if (!data || !data.ok) throw new Error('撤单失败，请刷新后重试')
  return data
}

// ---------- 缺料提醒 ----------

// 缺料上报走服务端 RPC：owner_id 必须写「缺料所属厨房的拥有者」（要被通知的人），
// 而不是上报的顾客，所以只能由数据库从厨房记录里取，前端不碰这个字段。
async function reportShortage(payload) {
  const problems = asArray(payload && payload.problems)
  if (!problems.length) return true
  await requireUser()
  const kitchenId = (payload && payload.kitchenId) || ''
  if (!kitchenId) return true
  const items = problems.map(function (item) {
    return {
      dish_name: String(item.dishes || (payload && payload.dishName) || '菜品'),
      ingredient_name: String(item.ingredientName || '食材'),
      needed: Number(item.needed || 0),
      stock: Number(item.stock || 0),
    }
  })
  unwrap(
    await cloud.database.rpc('report_shortage_atomic', {
      p_kitchen_id: Number(kitchenId),
      p_diner_name: String((payload && payload.dinerName) || '').trim() || null,
      p_items: items,
    })
  )
  return true
}

async function fetchShortageAlerts(kitchenId) {
  await requireUser()
  let query = cloud.database.from('shortage_alerts').select('*').eq('is_read', false)
  if (kitchenId) query = query.eq('kitchen_id', kitchenId)
  const rows = unwrap(await query.order('created_at', { ascending: false }).limit(50))
  return asArray(rows)
}

async function markShortageAlertsRead(ids) {
  const list = asArray(ids).filter(function (id) {
    return !!id
  })
  if (!list.length) return true
  await requireUser()
  unwrap(await cloud.database.from('shortage_alerts').update({ is_read: true }).in('id', list).select())
  return true
}

// 首页用：一次取回我所有厨房的「待接单」和「缺料」数量，避免逐个厨房发请求。
// 返回 { [kitchenId]: { pending: n, alerts: n } }
async function fetchKitchenBadges(kitchenIds, date) {
  const ids = asArray(kitchenIds).filter(function (id) {
    return !!id
  })
  if (!ids.length) return {}
  await requireUser()
  const result = {}
  ids.forEach(function (id) {
    result[id] = { pending: 0, alerts: 0 }
  })
  let ordersQuery = cloud.database
      .from('orders')
      .select('id, kitchen_id, status')
      .in('kitchen_id', ids)
      .eq('status', 'pending')
  if (date) ordersQuery = ordersQuery.eq('order_date', date)
  const tasks = [
    ordersQuery,
    cloud.database
      .from('shortage_alerts')
      .select('id, kitchen_id')
      .in('kitchen_id', ids)
      .eq('is_read', false),
  ]
  const settled = await Promise.all(
    tasks.map(function (task) {
      return Promise.resolve(task).then(
        function (res) {
          return asArray(res && res.data)
        },
        function () {
          return []
        }
      )
    })
  )
  asArray(settled[0]).forEach(function (row) {
    const bucket = result[row.kitchen_id]
    if (bucket && row.status === 'pending') bucket.pending += 1
  })
  asArray(settled[1]).forEach(function (row) {
    const bucket = result[row.kitchen_id]
    if (bucket) bucket.alerts += 1
  })
  return result
}

// ---------- 站内未读提醒 ----------
// 平台托管后端没有消息下发能力（没有订阅消息接口，小程序也出不了网），
// 所以订单提醒只做站内未读：由服务端 RPC 在订单事务里写入，
// 写失败会被子事务吞掉，绝不会连累订单本身。前端只读、只标记自己的。

async function fetchMyNotifications(options) {
  const user = await requireUser()
  const opts = options || {}
  let query = cloud.database
    .from('notifications')
    .select('*')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false })
    .limit(opts.limit || 50)
  if (opts.unreadOnly) query = query.eq('is_read', false)
  return asArray(unwrap(await query))
}

async function fetchUnreadNotificationCount() {
  const user = await requireUser()
  const result = await cloud.database
    .from('notifications')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', user.id)
    .eq('is_read', false)
  if (result && result.error) throw result.error
  return Number((result && result.count) || 0)
}

// 不传 ids 就是「全部标为已读」
async function markNotificationsRead(ids) {
  await requireUser()
  const list = asArray(ids).filter(function (id) {
    return !!id
  })
  if (ids !== undefined && ids !== null && !list.length) return 0
  const data = unwrap(
    await cloud.database.rpc('mark_notifications_read', {
      p_ids: list.length ? list : null,
      p_kitchen_id: null,
    })
  )
  return Number((data && data.marked) || 0)
}

module.exports = {
  reorderKitchenItems,
  ensureSession,
  requireUser,
  friendly,
  asArray,
  todayString,
  round1,
  fetchMyKitchens,
  fetchKitchen,
  fetchKitchensByIds,
  searchKitchens,
  searchDishes,
  createKitchen,
  getKitchenInvite,
  resetKitchenInvite,
  updateKitchen,
  deleteKitchen,
  fetchMembers,
  joinKitchenByCode,
  updateMember,
  removeMember,
  fetchKitchenBadges,
  fetchCategories,
  createCategory,
  updateCategory,
  deleteCategory,
  fetchDishes,
  countPublicDishes,
  listKitchenTags,
  fetchDish,
  createDish,
  updateDish,
  deleteDish,
  uploadDishImage,
  signImageUrls,
  fetchIngredients,
  createIngredient,
  updateIngredient,
  deleteIngredient,
  adjustStock,
  fetchStockLogs,
  fetchRecipes,
  replaceDishIngredients,
  buildAvailability,
  checkOrderAvailability,
  normalizeMealTime,
  mealTimeText,
  mealScheduleText,
  orderStatus,
  orderSteps,
  createOrder,
  fetchOrders,
  fetchMyOrders,
  fetchReceivedOrders,
  fetchOrder,
  fetchOrderItems,
  ackOrder,
  acceptOrder,
  finishOrder,
  rejectOrder,
  cancelOrder,
  fetchMyNotifications,
  fetchUnreadNotificationCount,
  markNotificationsRead,
  reportShortage,
  fetchShortageAlerts,
  markShortageAlertsRead,
}
