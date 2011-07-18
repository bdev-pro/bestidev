class UploadMonitor
  attr_accessor :product
  def initialize(folder)
    raise "Folder #{folder} not found" unless File.exists?(folder)
    @folder = folder
    raise "File #{products_file} not found" unless File.exists?(products_file)
    @product = nil
  end
  def products_file 
    File.join @folder, ExportConfig::PRODUCTS_FILE
  end
  def brand
    @folder.split("/").last.strip
  end
  def check_sku(sku)
    raise "Product id (#{sku}) already taken !" unless Product.active.select{|p|p.sku == sku}.empty?
  end
  def product_folder
    "#{@product.sku}_#{@product.name.gsub(" ","_")}"
  end
  def log(message, severity = :info)   
    @rake_log ||= ActiveSupport::BufferedLogger.new(File.join (@folder, "upload.log"))
    message = "[#{Time.now.to_s(:db)}] [#{severity.to_s.capitalize}] #{message}\n"
    @rake_log.send severity, message
    puts message
  end
  def associate_this_taxon(taxonomy_name, taxon_name)
    master_taxon = Taxonomy.find_by_name(taxonomy_name)
    if master_taxon.nil?
      master_taxon = Taxonomy.create(:name => taxonomy_name)
      log("Could not find Category taxonomy, so it was created.", :warn)
    end

    taxon = Taxon.find_or_create_by_name_and_parent_id_and_taxonomy_id(
      taxon_name, 
      master_taxon.root.id, 
      master_taxon.id
    )
    if taxon.save
      @product.taxons << taxon 
      log "#{taxon_name} associated to #{@product.name}"
    else
      log "#{taxon_name} not associated to #{@product.name}", :warn
    end
  end
  def find_and_attach_image(filename, product = @product)
    #An image has an attachment (duh) and some object which 'views' it
    product_image = Image.new({:attachment => File.open(filename, 'rb'), 
                              :viewable => product,
                              :position => product.images.length
    }) 
    if product_image.save
      product.images << product_image 
      log "#{File.basename(filename)} uploaded for #{product.name}"
    else
      log "#{File.basename(filename)} not uploaded for #{product.name}", :warn
    end
  end
  def find_and_assign_property_value(property_name, property_value)
    return if property_value.blank?
    # find or create the property itself
    property = Property.find_by_name(property_name)
    # make name equal presentation
    property = Property.create(:name => property_name, :presentation => property_name) if property.nil?
    # create the new product_property 
    pp = ProductProperty.new
    pp.product = @product
    pp.property = property
    pp.value = property_value
    pp.save
  end
end

class ProductUpload #< ActiveRecord::Base
  def self.upload_data(folder)
    begin
      m = UploadMonitor.new(folder)
      m.log "Start Upload of #{folder} stuff"
      File.open(m.products_file).readlines[1..-1].each do |row|
        product_info = {}
        m.product = nil
        # stuff from the CSV
        p = row.split(ExportConfig::CSV_SEP)
        ExportConfig::PROD_HEADER.each_with_index do |label, i|
          product_info[label.to_sym] = p[i]
          m.log "Read #{label} :" + product_info[label.to_sym]
        end
        # check that the sku is not taken!
        m.check_sku(product_info[:sku]) #  the most important line of this code :)
        # check that there are some images
        image_path = File.join folder, ExportConfig::IMAGES_FOLDER
        raise "Directory #{image_path} not found" unless File.exists?(image_path)
        imagefiles = Dir.new(image_path).entries.select{|f|f.include?(product_info[:sku])}
        raise "No images found for #{product_info[:sku]}" if imagefiles.empty?

        # here we can create the product already 
        section = product_info.delete(:section)
        m.product = Product.new(product_info)
        unless m.product.valid?
          log("A product could not be imported - :\n #{product_info.inspect}", :error)
          next
        end
        #Save the object before creating asssociated objects 
        m.product.save
        # associate taxa (brand and section)
        m.associate_this_taxon(ExportConfig::SECTION_TAXON, section)
        m.associate_this_taxon(ExportConfig::BRAND_TAXON, m.brand)

        # now images (one single folder for all images including those from the variants)
        m.log("#{imagefiles.size} found for #{m.product.sku}")
        imagefiles.each do |f| 
          m.find_and_attach_image(File.join(image_path, f))
        end

        # now stuff particular for the product
        product_folder = File.join(folder, m.product_folder)
        if File.exists?(product_folder)
          # desc
          desc_file = File.join product_folder, ExportConfig::DESC_FILE
          m.product.description = File.open(desc_file).read if File.exists?(desc_file)
          # meta desc
          metadesc_file = File.join product_folder, ExportConfig::METADESC_FILE
          m.product.meta_description = File.open(metadesc_file).read if File.exists?(metadesc_file)
          # properties
          prop_file = File.join product_folder, ExportConfig::PROPERTIES_FILE
          if File.exists?(prop_file)
            File.open(prop_file).readlines.each do |property|
              name, value = property.split(":")
              m.find_and_assign_property_value(name, value)
            end
          end
          m.product.save
          # variants (we assume we work with a single option value / type per product)
          variants_file = File.join product_folder, ExportConfig::VARIANTS_FILE
          if File.exists?(variants_file)
            File.open(variants_file).readlines[1..-1].each do |variant|
              v_info = {}
              variant_values = variant.split(ExportConfig::CSV_SEP)
              ExportConfig::VARIANT_HEADER.each_with_index do |label, i|
                v_info[label.to_sym] = variant_values[i]
              end
              m.log "Read variant #{v_info[:sku]} of #{m.product.sku} :" + v_info[:option_values]
              ot, val = v_info[:option_values].split(",")
              opt_type = m.product.option_types.select{|o| o.name == ot}.first # assume 1 
              opt_type = m.product.option_types.create(:name => ot, :presentation => ot.capitalize) if opt_type.nil?
              new_value = opt_type.option_values.create(:name => val, :presentation => val)
              ovariant = m.product.variants.create(:sku => v_info[:sku])
              ovariant.count_on_hand = v_info[:count_on_hand]
              ovariant.price = v_info[:price] unless v_info[:price].nil?
              ovariant.option_values << new_value
              image_path = File.join folder, ExportConfig::IMAGES_FOLDER
              imagefiles = Dir.new(image_path).entries.select{|f|f.include?(v_info[:sku])}
              unless imagefiles.empty?
                imagefiles.each{|f| m.find_and_attach_image(File.join(image_path, f), ovariant)} 
                m.log("#{imagefiles.size} found for variant #{v_info[:sku]} of #{m.product.sku}")
              end
              ovariant.save!
              m.log(" variant priced #{ovariant.price} with sku #{ovariant.price} saved for #{m.product.sku}")
            end
          end
        else
          m.log "No folder found for #{m.product_folder}"
        end

      end
      [:notice, "ran #{m.brand}, selected #{folder} at #{Time.now}"]
    rescue Exception => exp
      [:error, "error at #{Time.now}, #{exp.message}"]
    end
  end
end
