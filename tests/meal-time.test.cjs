const test = require('node:test')
const assert = require('node:assert/strict')
const { load, pageHarness } = require('./helpers.cjs')

test('今天按北京时间，UTC 午夜边界不受设备时区影响', () => {
  const meal = load('utils/meal-time.js')
  assert.equal(meal.todayString(new Date('2026-09-30T16:01:00Z')), '2026-10-01')
})

test('午夜前默认预约到次日，不产生跨午夜区间', () => {
  const meal = load('utils/meal-time.js')
  const value = meal.defaultSchedule(new Date('2026-09-30T15:30:00Z'))
  assert.equal(value.orderDate, '2026-10-01')
  assert.equal(value.timeStart, '00:30')
  assert.equal(value.timeEnd, '01:30')
  assert.equal(meal.defaultEndTime('23:30'), '')
})

test('未来日期不能选择尽快，过去日期不能提交', () => {
  const meal = load('utils/meal-time.js')
  assert.throws(() => meal.validateSchedule({ orderDate: '2026-10-01', mealTimeType: 'asap' }, '2026-09-30'), /尽快/)
  assert.throws(() => meal.validateSchedule({ orderDate: '2026-09-29', mealTimeType: 'point', mealTimeStart: '18:00' }, '2026-09-30'), /日期/)
})

test('时间格式和区间严格校验，允许开始时间之后不限结束', () => {
  const meal = load('utils/meal-time.js')
  assert.throws(() => meal.normalizeMealTime({ mealTimeType: 'point', mealTimeStart: '25:00' }), /时间/)
  assert.throws(() => meal.normalizeMealTime({ mealTimeType: 'point', mealTimeStart: '' }), /时间/)
  assert.equal(meal.normalizeMealTime({ mealTimeType: 'range', mealTimeStart: '18:00' }).meal_time_end, null)
})

test('预约日期上限与云端的今天加365天一致', () => {
  const meal = load('utils/meal-time.js')
  assert.throws(() => meal.validateSchedule({ orderDate: '2027-10-01', mealTimeType: 'point', mealTimeStart: '18:00' }, '2026-09-30'), /365/)
  assert.equal(meal.maxOrderDate('2026-09-30'), '2027-09-30')
  assert.equal(meal.validateSchedule({ orderDate: '2027-09-30', mealTimeType: 'point', mealTimeStart: '18:00' }, '2026-09-30').order_date, '2027-09-30')
})

test('选择未来日期后尽快改为时间点，清单包含日期', () => {
  const meal = load('utils/meal-time.js')
  const { page } = pageHarness('pages/cart/cart.js', {
    todayString: () => '2026-09-30', mealTimeText: meal.mealTimeText,
    mealScheduleText: meal.mealScheduleText,
  })
  page.data.mealType = 'asap'
  page.data.timeStart = '18:00'
  page.onMealDate({ detail: { value: '2026-10-01' } })
  assert.equal(page.data.mealType, 'point')
  assert.match(page.data.summary, /2026-10-01/)
})

test('撤单详情显示终止原因', async () => {
  const { page } = pageHarness('pages/order-detail/order-detail.js', {
    requireUser: async () => ({ id: 'diner' }),
    fetchOrder: async () => ({ id: 31, status: 'cancelled', diner_id: 'diner', kitchen_id: 12 }),
    fetchOrderItems: async () => [], fetchKitchen: async () => ({ name: '我家' }), fetchMembers: async () => [],
    orderStatus: () => ({ text: '已撤回', tone: 'off' }), orderSteps: () => [],
    mealTimeText: () => '', mealScheduleText: () => '', friendly: err => err.message,
  })
  page.orderId = 31
  await page.load()
  assert.match(page.data.statusHint, /撤回/)
})
