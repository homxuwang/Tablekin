const MAX_TAGS = 12
const MAX_TAG_LENGTH = 12

// 逗号和花括号会破坏 PostgREST 的数组字面量（`tags=cs.{川菜,辣}`），
// 引号会破坏它的字符串解析，控制字符会让展示错行。
// 服务端 CHECK 用的是同一套规则，这里再拦一遍是为了让错误在输入时就冒出来。
const ILLEGAL = /[,，、;；{}"'“”]/
const CONTROL = /[\t\n\r]/
// 输入「川菜 辣, 下饭」时按这些符号切开，一个输入框可以一次加好几个
const SEPARATOR = /[,，、;；\n\r\t]+/

function normalize(name) {
  return String(name == null ? '' : name).trim()
}

// 去掉空值、掐掉前后空白、按顺序去重（只认第一次出现的位置）
function clean(list) {
  const result = []
  ;(list || []).forEach(function (item) {
    const text = normalize(item)
    if (!text) return
    if (result.indexOf(text) >= 0) return
    result.push(text)
  })
  return result
}

// 校验一个标签，返回错误文案；合法返回空串
function validate(name) {
  const text = normalize(name)
  if (!text) return '标签不能为空'
  if (text.length > MAX_TAG_LENGTH) return '一个标签最多 ' + MAX_TAG_LENGTH + ' 个字'
  if (ILLEGAL.test(text)) return '标签里不能有逗号、顿号或引号'
  if (CONTROL.test(text)) return '标签里不能有换行'
  return ''
}

// 从菜品行里读标签：老数据没有 tags 字段时当空数组处理
function tags(dish) {
  return clean(Array.isArray(dish && dish.tags) ? dish.tags : [])
}

function add(list, name) {
  const text = normalize(name)
  if (!text) return clean(list)
  const result = clean(list)
  if (result.indexOf(text) >= 0) return result
  if (result.length >= MAX_TAGS) throw new Error('每道菜最多 ' + MAX_TAGS + ' 个标签')
  const error = validate(text)
  if (error) throw new Error(error)
  return result.concat(text)
}

function remove(list, name) {
  const text = normalize(name)
  return clean(list).filter(function (item) {
    return item !== text
  })
}

// 提交前过一遍：数量和单条合法性都在这里挡住，服务端 CHECK 是第二道
function fields(list) {
  const result = clean(list)
  if (result.length > MAX_TAGS) throw new Error('每道菜最多 ' + MAX_TAGS + ' 个标签')
  for (let i = 0; i < result.length; i += 1) {
    const error = validate(result[i])
    if (error) throw new Error(error)
  }
  return { tags: result }
}

// 把用户的一串输入切成标签列表，顺手做归一与去重
function parse(text) {
  return clean(String(text == null ? '' : text).split(SEPARATOR))
}

module.exports = {
  MAX_TAGS,
  MAX_TAG_LENGTH,
  tags,
  fields,
  clean,
  parse,
  validate,
  add,
  remove,
  normalize,
}
