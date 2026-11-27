const api = require('../../utils/api')
const cart = require('../../utils/cart')
const { confirmDelete } = require('../../utils/confirm-delete')
const dishImages = require('../../utils/dish-images')
const dishTags = require('../../utils/dish-tags')
const haptics = require('../../utils/haptics')

function toForm(dish) {
  return {
    name: (dish && dish.name) || '',
    description: (dish && dish.description) || '',
    recipe: (dish && dish.recipe) || '',
    is_public: dish ? !!dish.is_public : true,
    is_recipe_public: dish ? !!dish.is_recipe_public : false,
    is_available: dish ? !!dish.is_available : true,
    tags: dishTags.tags(dish),
    ...dishImages.fields(dishImages.paths(dish)),
  }
}

Page({
  data: {
    kitchenId: 0,
    loading: true,
    error: '',
    editMode: false,
    canEdit: false,
    dishId: 0,
    form: toForm(null),
    imageUrl: '',
    images: [],
    uploading: false,
    choosingImages: false,
    uploadProgress: '',
    categories: [],
    categoryLabels: [],
    categoryIndex: 0,
    ingredients: [],
    ingredientLabels: [],
    recipe: [],
    recipeVisible: false,
    saving: false,
    deleting: false,
    tags: [],
    tagInput: '',
    tagSuggestions: [],
    maxTags: dishTags.MAX_TAGS,
    cartQty: 0,
    cartTotal: 0,
  },

  onLoad(options) {
    this.kitchenId = Number((options && options.kitchenId) || 0)
    this.dishId = Number((options && options.id) || 0)
    this.presetCategoryId = Number((options && options.categoryId) || 0)
    this.wantEdit = !!(options && options.mode === 'edit')
    this.setData({ kitchenId: this.kitchenId, dishId: this.dishId })
    if (!this.kitchenId && !this.dishId) {
      this.setData({ loading: false, error: '没有指定厨房，请从首页重新进入' })
      return
    }
    this.load()
  },

  onShareAppMessage() {
    return {
      title: this.data.form.name || '看看这道菜',
      path: '/pages/dish/dish?id=' + this.dishId + '&kitchenId=' + this.kitchenId,
    }
  },

  load() {
    const that = this
    this.setData({ loading: true, error: '' })
    return api
      .requireUser()
      .then(function (user) {
        that.userId = user.id
        if (!that.kitchenId && that.dishId) {
          // 从分享卡片进来时可能没带厨房参数，就按菜品自己反推
          return api.fetchDish(that.dishId).then(function (dish) {
            if (!dish) throw new Error('这道菜不存在或已被删除')
            that.kitchenId = dish.kitchen_id
            that.setData({ kitchenId: dish.kitchen_id })
            return { kitchenId: dish.kitchen_id }
          })
        }
        return { kitchenId: that.kitchenId }
      })
      .then(function (payload) {
        return Promise.all([
          api.fetchKitchen(payload.kitchenId),
          api
            .fetchMembers(payload.kitchenId)
            .catch(function () {
              return []
            }),
        ])
      })
      .then(function (result) {
        const kitchen = result[0]
        const members = result[1] || []
        if (!kitchen) throw new Error('这个厨房不存在，或者你看不到它')
        const isMember = members.some(function (row) {
          return row.user_id === that.userId
        })
        that.isMember = isMember
        return Promise.all([
          api.fetchCategories({ kitchenId: that.kitchenId, publicOnly: !isMember }),
          isMember
            ? api.fetchIngredients({ kitchenId: that.kitchenId })
            : Promise.resolve([]),
          // 标签云只是输入建议，拿不到也不该挡住编辑
          api.listKitchenTags(that.kitchenId).catch(function () {
            return []
          }),
        ])
      })
      .then(function (result) {
        const categories = result[0] || []
        const ingredients = result[1] || []
        that.allTags = result[2] || []
        const labels = ['未分类'].concat(
          categories.map(function (item) {
            return item.name
          })
        )
        that.setData({
          categories: categories,
          categoryLabels: labels,
          ingredients: ingredients,
          ingredientLabels: ingredients.map(function (item) {
            return item.name + '（' + (item.unit || '份') + '）'
          }),
        })
        if (!that.dishId) {
          if (!that.isMember) throw new Error('你不是这个厨房的成员，不能新增菜品')
          that.startNewDish()
          return null
        }
        return api.fetchDish(that.dishId).then(function (dish) {
          if (!dish) throw new Error('这道菜不存在或已被删除')
          return dish
        })
      })
      .then(function (dish) {
        if (!dish) return null
        return that.presentDish(dish)
      })
      .catch(function (err) {
        that.setData({ loading: false, error: api.friendly(err) })
      })
  },

  startNewDish() {
    this.setData({
      loading: false,
      editMode: true,
      canEdit: true,
      dishId: 0,
      form: toForm(null),
      imageUrl: '',
      images: [],
      recipe: [],
      tags: [],
      tagInput: '',
      tagSuggestions: this.suggestionsFor([]),
      categoryIndex: this.indexForCategory(this.presetCategoryId),
      recipeVisible: true,
    })
    wx.setNavigationBarTitle({ title: '新增菜品' })
  },

  // ---------- 标签 ----------

  // 这个厨房用过的标签里，还没被这道菜选上的那些
  suggestionsFor(chosen) {
    const picked = dishTags.clean(chosen)
    return (this.allTags || []).filter(function (item) {
      return item && item.name && picked.indexOf(item.name) < 0
    })
  },

  syncTags(tags) {
    this.setData({ tags: tags, tagSuggestions: this.suggestionsFor(tags) })
  },

  onTagInput(event) {
    if (this.imageBusy()) return
    this.setData({ tagInput: event.detail.value })
  },

  // 输入框里可以一次打几个：「川菜 辣, 下饭」会切成三个
  confirmTag() {
    if (this.imageBusy()) return
    const pieces = dishTags.parse(this.data.tagInput)
    if (!pieces.length) {
      this.setData({ tagInput: '' })
      return
    }
    let tags = this.data.tags.slice()
    for (let i = 0; i < pieces.length; i += 1) {
      try {
        tags = dishTags.add(tags, pieces[i])
      } catch (err) {
        wx.showToast({ title: api.friendly(err), icon: 'none' })
        return
      }
    }
    this.setData({ tagInput: '' })
    this.syncTags(tags)
  },

  addSuggestion(event) {
    if (this.imageBusy()) return
    const name = event.currentTarget.dataset.name
    try {
      this.syncTags(dishTags.add(this.data.tags, name))
    } catch (err) {
      wx.showToast({ title: api.friendly(err), icon: 'none' })
    }
  },

  removeTag(event) {
    if (this.imageBusy()) return
    this.syncTags(dishTags.remove(this.data.tags, event.currentTarget.dataset.name))
  },

  indexForCategory(categoryId) {
    const categories = this.data.categories || []
    for (let i = 0; i < categories.length; i += 1) {
      if (categories[i].id === categoryId) return i + 1
    }
    return 0
  },

  // 把用料记录补上食材名称和单位，方便直接展示
  decorateRecipe(rows) {
    const ingredients = this.data.ingredients || []
    return (rows || []).map(function (row) {
      const found = ingredients.filter(function (item) {
        return item.id === row.ingredient_id
      })[0]
      return {
        ingredient_id: row.ingredient_id,
        amount: String(api.round1(row.amount)),
        name: found ? found.name : '（已删除的食材）',
        unit: found ? found.unit : '',
      }
    })
  },

  presentDish(dish) {
    const that = this
    const canEdit = !!this.isMember && dish.kitchen_id === this.kitchenId
    return Promise.all([
      api.signImageUrls(dishImages.paths(dish)),
      api.fetchRecipes({ dishId: dish.id }),
    ]).then(function (result) {
      const urls = result[0] || {}
      const recipes = result[1] || []
      that.setData({
        loading: false,
        canEdit: canEdit,
        editMode: canEdit && that.wantEdit,
        dishId: dish.id,
        form: toForm(dish),
        categoryIndex: that.indexForCategory(dish.category_id),
        recipeVisible: canEdit || !!dish.is_recipe_public,
        recipe: that.decorateRecipe(recipes),
        tags: dishTags.tags(dish),
        tagInput: '',
        tagSuggestions: that.suggestionsFor(dishTags.tags(dish)),
      })
      that.setImages(dishImages.paths(dish), urls)
      that.syncDishCart()
      wx.setNavigationBarTitle({ title: dish.name || '菜品详情' })
    })
  },

  toggleEdit() {
    if (!this.data.canEdit || this.data.saving || this.data.deleting || this.data.uploading || this.data.choosingImages) return
    this.setData({ editMode: !this.data.editMode })
  },

  onInput(event) {
    if (this.imageBusy()) return
    const patch = {}
    patch['form.' + event.currentTarget.dataset.field] = event.detail.value
    this.setData(patch)
  },

  onSwitch(event) {
    if (this.imageBusy()) return
    const patch = {}
    patch['form.' + event.currentTarget.dataset.field] = event.detail.value
    this.setData(patch)
  },

  onCategoryChange(event) {
    if (this.imageBusy()) return
    this.setData({ categoryIndex: Number(event.detail.value) })
  },

  // ---------- 用料 ----------

  onPickIngredient(event) {
    if (this.imageBusy()) return
    const index = Number(event.detail.value)
    const ingredient = this.data.ingredients[index]
    if (!ingredient) return
    const recipe = this.data.recipe.slice()
    const exists = recipe.some(function (item) {
      return item.ingredient_id === ingredient.id
    })
    if (exists) {
      wx.showToast({ title: '这个食材已经加过了', icon: 'none' })
      return
    }
    recipe.push({
      ingredient_id: ingredient.id,
      amount: '',
      name: ingredient.name,
      unit: ingredient.unit || '份',
    })
    this.setData({ recipe: recipe })
  },

  onRecipeAmountInput(event) {
    if (this.imageBusy()) return
    const index = Number(event.currentTarget.dataset.index)
    const patch = {}
    patch['recipe[' + index + '].amount'] = event.detail.value
    this.setData(patch)
  },

  removeRecipeRow(event) {
    if (this.imageBusy()) return
    const index = Number(event.currentTarget.dataset.index)
    const recipe = this.data.recipe.slice()
    recipe.splice(index, 1)
    this.setData({ recipe: recipe })
  },

  goIngredients() {
    if (this.imageBusy()) return
    wx.navigateTo({ url: '/pages/ingredients/ingredients?kitchenId=' + this.kitchenId })
  },

  // ---------- 图片 ----------

  setImages(paths, urls) {
    this._imageUrls = Object.assign({}, this._imageUrls || {}, urls || {})
    const fields = dishImages.fields(paths)
    const images = fields.image_paths.map(path => ({ path, url: this._imageUrls[path] || '' }))
    this.setData({
      form: Object.assign({}, this.data.form, fields),
      images,
      imageUrl: images.length ? images[0].url : '',
    })
  },

  imageBusy() {
    return !this.data.canEdit || !this.data.editMode || this.data.saving || this.data.deleting || this.data.uploading || this.data.choosingImages
  },

  chooseImage() {
    if (this.imageBusy()) return
    const count = dishImages.MAX_IMAGES - this.data.images.length
    if (count <= 0) {
      wx.showToast({ title: '每道菜最多9张图片', icon: 'none' })
      return
    }
    this.setData({ choosingImages: true })
    wx.chooseMedia({
      count,
      mediaType: ['image'],
      sizeType: ['compressed'],
      success: res => {
        this.setData({ choosingImages: false })
        this.uploadImages(res.tempFiles || [])
      },
      fail: err => {
        this.setData({ choosingImages: false })
        if (!/cancel/i.test((err && err.errMsg) || '')) {
          wx.showToast({ title: '无法选择图片，请重试', icon: 'none' })
        }
      },
    })
  },

  async uploadImages(files) {
    if (this.imageBusy()) return
    const selected = files.filter(file => file && file.tempFilePath)
      .slice(0, dishImages.MAX_IMAGES - this.data.images.length)
    if (!selected.length) return
    this.setData({ uploading: true })
    let failed = 0
    let lastError = ''
    wx.showLoading({ title: '上传中', mask: true })
    try {
      for (let i = 0; i < selected.length; i += 1) {
        this.setData({ uploadProgress: '上传 ' + (i + 1) + '/' + selected.length })
        const file = selected[i]
        try {
          const path = await api.uploadDishImage(file.tempFilePath)
          // 先保留上传结果；签名失败也不能丢失已上传路径。
          this.setImages(this.data.form.image_paths.concat(path), { [path]: file.tempFilePath })
          try {
            const urls = await api.signImageUrls([path])
            this.setImages(this.data.form.image_paths, urls)
          } catch (err) { /* 本地图片仍可预览，重新加载时重签名。 */ }
        } catch (err) {
          failed += 1
          lastError = api.friendly(err)
        }
      }
    } finally {
      wx.hideLoading()
      this.setData({ uploading: false, uploadProgress: '' })
    }
    if (failed) {
      wx.showModal({ title: '部分图片上传失败', content: failed + ' 张未上传，成功图片已保留。可重新选择失败图片。' + lastError, showCancel: false })
    }
  },

  setCover(event) {
    if (this.imageBusy()) return
    this.setImages(dishImages.cover(this.data.form.image_paths, event.currentTarget.dataset.path))
  },

  removeImage(event) {
    if (this.imageBusy()) return
    const path = event.currentTarget.dataset.path
    this.setImages(this.data.form.image_paths.filter(item => item !== path))
  },

  previewImages(event) {
    const images = this.data.images.filter(item => item.url)
    const found = images.find(item => item.path === event.currentTarget.dataset.path)
    if (!found) {
      wx.showToast({ title: '图片暂不可用，请重新进入页面', icon: 'none' })
      return
    }
    wx.previewImage({ current: found.url, urls: images.map(item => item.url) })
  },

  // ---------- 保存 / 删除 ----------

  save() {
    const that = this
    if (this.imageBusy()) return
    const form = this.data.form
    const name = String(form.name || '').trim()
    if (!name) {
      wx.showToast({ title: '请先填写菜名', icon: 'none' })
      return
    }
    const recipe = (this.data.recipe || []).map(item => Object.assign({}, item))
    for (let i = 0; i < recipe.length; i += 1) {
      const amount = Number(recipe[i].amount)
      if (!amount || amount <= 0) {
        wx.showToast({ title: '请填写「' + recipe[i].name + '」每份用量', icon: 'none' })
        return
      }
    }
    const category = this.data.categories[this.data.categoryIndex - 1]
    const payload = {
      name: name,
      description: String(form.description || '').trim() || null,
      recipe: String(form.recipe || '').trim() || null,
      category_id: category ? category.id : null,
      is_public: !!form.is_public,
      is_recipe_public: !!form.is_recipe_public,
      is_available: !!form.is_available,
      ...dishImages.fields(form.image_paths),
      ...dishTags.fields(this.data.tags),
    }
    this.setData({ saving: true })
    const task = this.data.dishId
      ? api.updateDish(this.data.dishId, payload)
      : api.createDish(Object.assign({}, payload, { kitchen_id: this.kitchenId }))
    return task
      .then(function (dish) {
        const dishId = that.data.dishId || (dish && dish.id)
        if (!dishId) throw new Error('菜品没有保存成功，请重试')
        // 配方保存失败时，重试应修改已有菜品，避免重复创建。
        that.setData({ dishId })
        that.dishId = dishId
        return api.replaceDishIngredients(
          dishId,
          that.kitchenId,
          recipe.map(function (item) {
            return { ingredient_id: item.ingredient_id, amount: Number(item.amount) }
          })
        )
      })
      .then(function () {
        that.setData({ saving: false })
        wx.showToast({ title: '已保存', icon: 'success' })
        setTimeout(function () {
          wx.navigateBack()
        }, 600)
      })
      .catch(function (err) {
        that.setData({ saving: false })
        wx.showModal({ title: '保存失败', content: api.friendly(err), showCancel: false })
      })
  },

  async remove() {
    if (this.imageBusy() || !this.data.dishId) return
    this.setData({ deleting: true })
    try {
      if (!await confirmDelete({ title: '删除「' + this.data.form.name + '」？', content: '删除后无法恢复，菜谱和用料会一起删除。' }, wx)) return
      await api.deleteDish(this.data.dishId)
      this.setData({ canEdit: false, editMode: false })
      wx.showToast({ title: '已删除', icon: 'success' })
      wx.navigateBack()
    } catch (err) {
      wx.showModal({ title: '删除失败', content: api.friendly(err), showCancel: false })
    } finally {
      this.setData({ deleting: false })
    }
  },

  syncDishCart() {
    if (!this.kitchenId || !this.dishId) return
    const current = cart.readCart(this.kitchenId)
    const entry = current[this.dishId]
    this.setData({
      cartQty: entry && entry.count > 0 ? entry.count : 0,
      cartTotal: cart.totalCount(current),
    })
  },

  addDishToCart() {
    if (!this.kitchenId || !this.dishId) return
    if (!this.data.form.is_available) {
      wx.showToast({ title: '这道菜已下架，暂时点不了', icon: 'none' })
      return
    }
    const current = cart.readCart(this.kitchenId)
    const entry = current[this.dishId] || { id: this.dishId, name: this.data.form.name, count: 0 }
    entry.name = this.data.form.name || entry.name
    entry.kitchen_id = this.kitchenId
    entry.count = entry.count + 1
    current[this.dishId] = entry
    cart.writeCart(this.kitchenId, current)
    haptics.light()
    this.syncDishCart()
    wx.showToast({ title: '已加入清单', icon: 'success', duration: 900 })
  },

  decreaseDishFromCart() {
    if (!this.kitchenId || !this.dishId) return
    const current = cart.readCart(this.kitchenId)
    const entry = current[this.dishId]
    if (!entry) return
    if (entry.count <= 1) delete current[this.dishId]
    else entry.count = entry.count - 1
    cart.writeCart(this.kitchenId, current)
    haptics.light()
    this.syncDishCart()
  },

  goCartFromDish() {
    if (!this.kitchenId) return
    wx.navigateTo({ url: '/pages/cart/cart?kitchenId=' + this.kitchenId })
  },

  goKitchenMenu() {
    if (!this.kitchenId) return
    const pages = getCurrentPages()
    const prev = pages.length > 1 ? pages[pages.length - 2] : null
    const from = prev ? prev.route : ''
    // 从菜单页进来的就退回去，从搜索页进来的就直接换成菜单页，别越堆越深
    if (from === 'pages/menu/menu') {
      wx.navigateBack()
      return
    }
    const url = '/pages/menu/menu?kitchenId=' + this.kitchenId
    if (from === 'pages/search/search') {
      wx.redirectTo({ url: url })
      return
    }
    wx.navigateTo({ url: url })
  },
})
