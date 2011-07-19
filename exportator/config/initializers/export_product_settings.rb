class ExportConfig
  BRAND_TAXON = "Marcas"
  SECTION_TAXON = "Productos"
  EXPORT_FOLDER = File.join Rails.root, "xtra/catalogo/exported" # DEVELOPMENT!!
  LOGFILE = File.join(EXPORT_FOLDER, "export_products_#{Rails.env}.log")
  PROD_HEADER = %w(section sku name price cost_price count_on_hand visibility available_on show_on_homepage meta_keywords)
  VARIANT_HEADER = %w(sku count_on_hand price option_values) 
  CSV_SEP = "|"

  # trivial names
  DESC_FILE = "desc.txt"
  METADESC_FILE = "metadesc.txt"
  PROPERTIES_FILE = "properties.txt"
  VARIANTS_FILE = "variants.csv"
  PRODUCTS_FILE = "products.csv"

  IMAGES_FOLDER = "images"
  IMAGES_DESC_FILE = "images_descriptions.txt"

  # exporter only
  SUMMARY_FILE = "resumen.csv"
end
