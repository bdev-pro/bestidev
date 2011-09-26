require 'fileutils'


class ProductInfo
  attr_reader :num_images
  def initialize(product, brand_folder)
    @p = product
    @desc = {:file => ExportConfig::DESC_FILE , :text => @p.description}
    @metadesc = {:file => ExportConfig::METADESC_FILE, :text => @p.meta_description}
    @folder = File.join brand_folder, @p.sku
    FileUtils.mkdir_p(@folder)
    @images_folder = File.join @folder, ExportConfig::IMAGES_FOLDER 
    FileUtils.mkdir_p(@images_folder)
    @num_images = 0
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
      File.open(File.join(@folder, ExportConfig::PROPERTIES_FILE), "w") do |f|
        @p.product_properties.each do |prop|
          f.puts Property.find(prop.property_id).name + ":" + prop.value
        end
      end
      num_props = @p.product_properties.size
    end
    num_props
  end
  def image_desc(sku, image)
    @num_images += 1
    [sku, image.attachment_file_name, image.alt].join(':')
  end
  def export_images
    File.open(File.join(@images_folder, ExportConfig::IMAGES_DESC_FILE), "w") do |f|
      f.puts ExportConfig::IMAGES_DESC_HEADER 
      if @p.images.empty?
        elog "NO image for #{@p.name}, sku #{@p.sku}", :warn 
      else
        @p.images.each {|image| f.puts image_desc(@p.sku, image)} 
      end
    end
    # now export the images of the variants
    if @p.has_variants?
      File.open(File.join(@images_folder, ExportConfig::VARIANTS_IMAGES_DESC_FILE), "w") do |f|
        f.puts ExportConfig::IMAGES_DESC_HEADER 
        @p.variants.each do |variant|
          variant.images.each {|image| f.puts image_desc(variant.sku, image)} unless variant.images.empty?
        end
      end
    end
  end
  def export_variants
    csv_sep = ExportConfig::CSV_SEP
    if @p.has_variants?
      File.open(File.join(@folder, ExportConfig::VARIANTS_FILE), "w") do |f|
        f.puts ExportConfig::VARIANT_HEADER.join(csv_sep)
        @p.variants.each do |v|
          elog "var"
          vstr = [v.sku, v.count_on_hand, v.price].map{|x| x.to_s}.join(csv_sep)
          # now addd the single option type (there could be more...)
          raise "#{v.option_values.size} option values for #{v.name}, 1 expected" unless v.option_values.size == 1
          ov = v.option_values.first
          elog "ov"
          ot = OptionType.find(ov.option_type.id)
          elog "ot preosentation: #{ot.presentation}"
          elog "ov preosentation: #{ov.presentation}"
          raise "no presentation" if ot.presentation.nil?
          vstr += csv_sep + ot.presentation + ':' + ov.presentation
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
  @rake_log ||= ActiveSupport::BufferedLogger.new(ExportConfig::LOGFILE)
  message = "[#{Time.now.to_s(:db)}] [#{severity.to_s.capitalize}] #{message}\n"
  @rake_log.send severity, message
  puts message
end

class ProductExport 
  def self.export_data
    ret = ""
    begin
      elog "NEW export started"
      csv_sep = ExportConfig::CSV_SEP
      # check the brands
      brands_id = Taxon.find_by_name(ExportConfig::BRAND_TAXON).id      # This is the id for "Marcas" 
      brands = Taxon.select{|t| t.parent_id == brands_id}               # Find all brands
      products = []
      f_full = File.open(File.join(ExportConfig::EXPORT_FOLDER, ExportConfig::SUMMARY_FILE), "w")
      f_full.puts 'brand' + csv_sep + ExportConfig::PROD_HEADER.join(csv_sep)
      brands.sort{|a,b| a.name <=> b.name}.each do |brand|
        brand_folder = File.join ExportConfig::EXPORT_FOLDER, brand.name.gsub(" ","_")
        FileUtils.mkdir_p(brand_folder)
        # which products are in the database for this brand?
        searcher = Spree::Config.searcher_class.new(:taxon => brand.id)
        products = searcher.retrieve_products
        elog "Start with #{brand.name} : #{products.size} products" 
        num_prods = 0
        File.open(File.join(brand_folder, ExportConfig::PRODUCTS_FILE), "w") do |f| # create a csv file per brand
          f.puts ExportConfig::PROD_HEADER.join(csv_sep)
          products.each do |p|
            num_prods += 1
            pi = ProductInfo.new(p, brand_folder) 
            elog " starting (#{num_prods}) #{p.sku} #{p.name}"
            if p.taxons.empty?  
              elog " no section for #{p.name}", :warn 
              sections = ""
            else
              sections = p.taxons.map{|t| t.permalink}.join(" ")
            end
            pstr = [sections || "", pi.to_csv_str(csv_sep)].join(csv_sep)
            f_full.puts [brand.name, pstr].join(csv_sep)
            f.puts pstr 
            elog "export descriptions"
            pi.export_descriptions
            elog "export properties"
            num_props = pi.export_properties
            elog "export images"
            pi.export_images
            elog "export variants"
            num_variants = pi.export_variants
            elog " exported incl. #{num_props} properties, #{pi.num_images} images, #{num_variants} variants"
          end
        end
      end
      elog " Finished export,  my friend :) "
      f_full.close
    [:notice, "You did it :) at #{Time.now}, now go and check your files at #{ExportConfig::EXPORT_FOLDER}  \n" +  ret]
    rescue Exception => exp
      [:error, "error at #{Time.now}, #{exp.message}"]
    end
  end
end

