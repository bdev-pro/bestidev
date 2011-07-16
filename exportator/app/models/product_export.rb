require 'fileutils'
#constants/config
BRAND_TAXON = "Marcas"
SECTION_TAXON = "Productos"
EXPORT_FOLDER = File.join Rails.root, "xtra/catalogo/exported" # DEVELOPMENT!!
PROD_HEADER = %w(section sku name price cost_price count_on_hand visibility available_on show_on_homepage meta_keywords)
VARIANT_HEADER = %w(sku count_on_hand price option_values images) 
CSV_SEP = "\t"
#LOGFILE = File.join(Rails.root, '/log/', "export_products_#{Rails.env}.log")
LOGFILE = File.join(EXPORT_FOLDER, "export_products_#{Rails.env}.log")

class ProductInfo
  def initialize(product, brand_folder)
    @p = product
    @desc = {:file => "desc.txt", :text => @p.description}
    @metadesc = {:file => "metadesc.txt", :text => @p.meta_description}
    @folder = File.join brand_folder, "#{@p.sku}_#{@p.name.gsub(" ","_")}"
    FileUtils.mkdir_p(@folder)
  end
  def to_csv_str(sep) 
    str = @p.sku.to_s
    str += sep + @p.name.to_s
    str += sep + @p.price.to_s 
    str += sep + @p.cost_price.to_s 
    str += sep + @p.count_on_hand.to_s
    str += sep + @p.visibility.to_s
    str += sep + @p.available_on.to_s
    str += sep + @p.show_on_homepage.to_s
    str += sep + @p.meta_keywords.to_s
  end
  def export_descriptions
    [@desc, @metadesc].each do |desc|
      File.open(File.join(@folder, desc[:file]), "w"){ |f| f.puts desc[:text]}
    end
  end
  def export_properties
    if @p.product_properties.empty?
      num_props = 0
    else
      File.open(File.join(@folder, "properties.txt"), "w") do |f|
        @p.product_properties.each do |prop|
          f.puts Property.find(prop.property_id).name + ":" + prop.value
        end
      end
      num_props = @p.product_properties.size
    end
    num_props
  end
  def export_images
    if @p.images.empty?
      num_images = 0
    else
      File.open(File.join(@folder, "images.txt"), "w") do |f|
        @p.images.each do |image|
          f.puts image.attachment_file_name
        end
      end
      num_images = @p.images.size
    end
    num_images
  end
  def export_variants
    if @p.has_variants?
      File.open(File.join(@folder, "variants.txt"), "w") do |f|
        f.puts VARIANT_HEADER.join(CSV_SEP)
        @p.variants.each do |v|
          vstr = [v.sku, v.count_on_hand, v.price].map{|x| x.to_s}.join(CSV_SEP)
          # now addd the single option type (there could be more...)
          raise "#{v.option_values.size} option values for #{v.name}, 1 expected" unless v.option_values.size == 1
          ov = v.option_values.first
          ot = OptionType.find(ov.option_type.id)
          vstr += CSV_SEP + ot.presentation + ':' + ov.presentation
          # now check the images, if any, if image is missing report
          if v.images.empty?
            num_images = 0
            elog "  No image found for variant #{v.sku}"
          else
            vstr += CSV_SEP + "images:" + v.images.map{|i|i.attachment_file_name}.join(",")
            num_images = v.images.size
          end
          f.puts vstr
        end
      end
      num_variants = @p.variants.size
    else
      num_variants = 0
    end
  end
end

# helpers for cleaner code
def elog(message, severity = :info)   
  @rake_log ||= ActiveSupport::BufferedLogger.new(LOGFILE)
  message = "[#{Time.now.to_s(:db)}] [#{severity.to_s.capitalize}] #{message}\n"
  @rake_log.send severity, message
  puts message
end

class ProductExport 
  def self.export_data
    ret = ""
    begin
      File.delete(LOGFILE)
      elog "NEW export, all previous will be overwritten"
      # hash the sections
      hsections = {}
      sections_id = Taxon.find_by_name(SECTION_TAXON).id      
      sections = Taxon.select{|t| t.parent_id == sections_id} 
      sections.each do |section|
        searcher = Spree::Config.searcher_class.new(:taxon => section.id)
        products = searcher.retrieve_products
        products.each do |p|
          hsections[p.id] = section.name
        end
      end

      # check the brands
      brands_id = Taxon.find_by_name(BRAND_TAXON).id      # This is the id for "Marcas" 
      brands = Taxon.select{|t| t.parent_id == brands_id} # Find all brands
      products = []
      f_full = File.open(File.join(EXPORT_FOLDER,"resumen.csv"), "w")
      f_full.puts 'brand' + CSV_SEP + PROD_HEADER.join(CSV_SEP)
      brands.sort{|a,b| a.name <=> b.name}.each do |brand|
        brand_folder = File.join EXPORT_FOLDER, brand.name.gsub(" ","_")
        FileUtils.mkdir_p(brand_folder)
        # which products are in the database for this brand?
        searcher = Spree::Config.searcher_class.new(:taxon => brand.id)
        products = searcher.retrieve_products
        elog "Start with #{brand.name} : #{products.size} products" 
        num_prods = 0
        File.open(File.join(brand_folder, "products.csv"), "w") do |f| # create a csv file per brand
          f.puts PROD_HEADER.join(CSV_SEP)
          products.each do |p|
            num_prods += 1
            pi = ProductInfo.new(p, brand_folder) 
            elog " starting (#{num_prods}) #{p.sku} #{p.name}"
            elog " no section for #{p.name}", :warn if hsections[p.id].nil?
            pstr = [hsections[p.id] || "", pi.to_csv_str(CSV_SEP)].join(CSV_SEP)
            f_full.puts [brand.name, pstr].join(CSV_SEP)
            f.puts pstr 
            pi.export_descriptions
            num_props = pi.export_properties
            num_images = pi.export_images
            num_variants = pi.export_variants
            elog " exported incl. #{num_props} properties, #{num_images} images, #{num_variants} variants"
            elog "NO image for #{p.name}", :warn if num_images == 0
          end
        end
      end
      f_full.close
    [:notice, "You did it :) at #{Time.now}, now go and check your files at #{EXPORT_FOLDER}  \n" +  ret]
    rescue Exception => exp
      [:error, "error at #{Time.now}, #{exp.message}"]
    end
  end
end

