const OFFSET = 8 * 60 * 60 * 1000
function pad(value) { return value < 10 ? '0' + value : String(value) }
function chinaTime(now) { return new Date((now || new Date()).getTime() + OFFSET) }
function dateText(date) {
  return date.getUTCFullYear() + '-' + pad(date.getUTCMonth() + 1) + '-' + pad(date.getUTCDate())
}
function todayString(now) { return dateText(chinaTime(now)) }
function maxOrderDate(today) {
  return dateText(new Date(new Date((today || todayString()) + 'T00:00:00Z').getTime() + 365 * 86400000))
}

function validDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
  const parsed = new Date(value + 'T00:00:00Z')
  return !isNaN(parsed.getTime()) && dateText(parsed) === value
}
function validTime(value) { return /^([01]\d|2[0-3]):[0-5]\d$/.test(value) }

function normalizeMealTime(payload) {
  const type = (payload && payload.mealTimeType) || 'point'
  const start = String((payload && payload.mealTimeStart) || '').trim()
  const end = String((payload && payload.mealTimeEnd) || '').trim()
  if (type === 'asap') return { meal_time_type: type, meal_time_start: null, meal_time_end: null }
  if ((type !== 'point' && type !== 'range') || !validTime(start)) throw new Error('请选一个有效的就餐时间')
  if (type === 'range' && end && (!validTime(end) || end <= start)) {
    throw new Error('结束时间须晚于开始时间；跨午夜请分开预约')
  }
  return { meal_time_type: type, meal_time_start: start, meal_time_end: type === 'range' ? end || null : null }
}

function validateSchedule(payload, today) {
  const current = today || todayString()
  const day = String((payload && payload.orderDate) || current)
  if (!validDate(day) || day < current) throw new Error('请选择今天或之后的有效就餐日期')
  if (day > maxOrderDate(current)) throw new Error('就餐日期最多可预约未来365天')
  const meal = normalizeMealTime(payload)
  if (meal.meal_time_type === 'asap' && day !== current) throw new Error('尽快仅适用于今天，请为预约日期选择时间')
  return Object.assign({ order_date: day }, meal)
}

function mealTimeText(order) {
  const type = (order && order.meal_time_type) || 'point'
  const start = (order && order.meal_time_start) || ''
  const end = (order && order.meal_time_end) || ''
  if (type === 'asap' || !start) return '尽快'
  if (type === 'range') return end ? start + '–' + end : start + ' 之后'
  return start
}
function mealScheduleText(order) {
  return ((order && order.order_date) ? order.order_date + ' · ' : '') + mealTimeText(order)
}
function defaultEndTime(start) {
  if (!validTime(start)) return ''
  const parts = start.split(':')
  const end = Number(parts[0]) * 60 + Number(parts[1]) + 60
  return end >= 1440 ? '' : pad(Math.floor(end / 60)) + ':' + pad(end % 60)
}
function defaultSchedule(now) {
  let value = chinaTime(now)
  const hour = value.getUTCHours()
  let start
  if (hour < 11) start = '12:00'
  else if (hour < 17) start = '18:30'
  else {
    value = new Date(value.getTime() + 60 * 60 * 1000)
    start = pad(value.getUTCHours()) + ':' + pad(value.getUTCMinutes())
  }
  return { orderDate: dateText(value), timeStart: start, timeEnd: defaultEndTime(start) }
}

module.exports = { todayString, maxOrderDate, normalizeMealTime, validateSchedule, mealTimeText, mealScheduleText, defaultEndTime, defaultSchedule }
