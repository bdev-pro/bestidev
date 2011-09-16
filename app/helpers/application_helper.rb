module ApplicationHelper
  def taxon(name)
    # Shop by Productos, carefull if we change Taxonomy!
    #Taxonomy.find_by_name("Productos").root.children.find_by_name(name)
    # Shop by first option, less likely to chanche:
    Taxonomy.all.first.root.children.find_by_name(name)
  end
  def subcategories_of(name)
    # returns the subcategories
    taxon_id = Taxon.find_by_name(name).id
    Taxon.select{|t| t.parent_id == taxon_id}
  end
  def brand_url(brand)
    taxonomies = Taxonomy.find_by_name("Marcas").root.children
    brand_t = taxonomies.find_by_name(brand) || taxonomies.first
    seo_url(brand_t)
  end
  def variant_price_diff_format(variant)
    return product_price(variant) unless variant.product.master.price
    diff = product_price(variant, :format_as_currency => false) - product_price(variant.product, :format_as_currency => false)
    if diff == 0
      return nil
    else
      return ", #{t("price")}: " + product_price(variant)
    end
  end
end
