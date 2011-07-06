#constants
BRAND_TAXON = "Marcas"
SECTION_TAXON = "Productos"
EXPORT_FOLDER = "/home/fernando/webdev/RoR/beshop/xtra/catalogo/exported" # DEVELOPMENT!!


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
        # which products are in the database for this brand?
        searcher = Spree::Config.searcher_class.new(:taxon => brand.id)
        products = searcher.retrieve_products
        ret += "#{brand.name} : #{products.size},  " # just what we show on the web
        File.open(File.join(EXPORT_FOLDER, brand.name + ".csv"), "w") do |f| # create a csv file per brand
          products.each do |p|
            str = p.name 
            str += ' ' + h[p.id] if h.has_key?(p.id) # TODO make sure the product has a section 
            f.puts str 
          end
        end
      end
    [:notice, "You did it :) at #{Time.now}, now find your files at #{EXPORT_FOLDER}  \n" +  ret]
    rescue Exception => exp
      [:error, "error at #{Time.now}, #{exp.message}"]
    end
  end
end
