require 'fileutils'
#constants
BRAND_TAXON = "Marcas"
SECTION_TAXON = "Productos"
EXPORT_FOLDER = "/home/fernando/webdev/RoR/beshop/xtra/catalogo/exported" # DEVELOPMENT!!
PROD_HEADER = %w(sku name price cost_price count_on_hand visibility available_on show_on_homepage meta_keywords)


class ProductExport 
  def self.export_data
    ret = ""
    begin
      # hash the sections
      h = {}
      sections_id = Taxon.find_by_name(SECTION_TAXON).id      
      sections = Taxon.select{|t| t.parent_id == sections_id} 
      sections.each do |section|
        searcher = Spree::Config.searcher_class.new(:taxon => section.id)
        products = searcher.retrieve_products
        products.each do |p|
          h[p.id] = section.name
        end
      end

      # check the brands
      brands_id = Taxon.find_by_name(BRAND_TAXON).id      # This is the id for "Marcas" 
      brands = Taxon.select{|t| t.parent_id == brands_id} # Find all brands
      products = []
      brands.each do |brand|
        brand_folder = File.join EXPORT_FOLDER, brand.name.gsub(" ","_")
        FileUtils.mkdir_p(brand_folder)
        # which products are in the database for this brand?
        searcher = Spree::Config.searcher_class.new(:taxon => brand.id)
        products = searcher.retrieve_products
        ret += "#{brand.name} : #{products.size},  " # just what we show on the web
        File.open(File.join(brand_folder, "products.csv"), "w") do |f| # create a csv file per brand
          f.puts PROD_HEADER.join('|')
          products.each do |p|
            str = p.sku.to_s
            str += '|' + p.name.to_s
            str += '|' + p.price.to_s 
            str += '|' + p.cost_price.to_s 
            str += '|' + p.count_on_hand.to_s
            str += '|' + p.visibility.to_s
            str += '|' + p.available_on.to_s
            str += '|' + p.show_on_homepage.to_s
            str += '|' + p.meta_keywords.to_s
            f.puts str 
            product_folder = File.join brand_folder, "#{p.sku}_#{p.name.gsub(" ","_")}"
            FileUtils.mkdir_p(product_folder)
            File.open(File.join(product_folder, "desc.txt"), "w"){ |fdesc| fdesc.puts p.description}
            File.open(File.join(product_folder, "metadesc.txt"), "w"){ |fmdesc| fmdesc.puts p.meta_description}
          end
        end
      end
    [:notice, "You did it :) at #{Time.now}, now find your files at #{EXPORT_FOLDER}  \n" +  ret]
    rescue Exception => exp
      [:error, "error at #{Time.now}, #{exp.message}"]
    end
  end
end
