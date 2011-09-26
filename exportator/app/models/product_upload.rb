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
  def check_sku_available(sku)
    Product.active.select{|p|p.sku == sku}.empty?
  end
  def product_folder
    @product.sku
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
  def associate_subcategory(taxonomy_name, parent_taxon_name, taxon_name)
    taxon = Taxon.find_or_create_by_name_and_parent_id_and_taxonomy_id(
      taxon_name, 
      Taxon.find_by_name(parent_taxon_name).id,
      Taxonomy.find_by_name(taxonomy_name) 
    )
    if taxon.save
      @product.taxons << taxon 
      log "#{taxon_name} associated to #{@product.name}"
    else
      log "#{taxon_name} not associated to #{@product.name}", :warn
    end
  end
  def find_and_attach_image(filename, product, alt_desc = "")
    #An image has an attachment (duh) and some object which 'views' it
    product_image = Image.new({:attachment => File.open(filename, 'rb'), 
                              :viewable => product,
                              :position => product.images.length, 
                              :alt => alt_desc
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
  def check_image(image_path)
    log " image path is #{image_path}"
    num_images = 0
    if File.exists?(image_path)
      image_desc_file = File.join image_path, ExportConfig::IMAGES_DESC_FILE
      if File.exists?(image_desc_file)
        File.open(image_desc_file).readlines[1..-1].each do |image_row|
          sku, image_name, alt_desc = image_row.chomp.split(":")
          next if sku.nil? or image_name.nil? 
          imagefiles = Dir.new(image_path).entries.select{|f|f.include?(image_name)}
          if imagefiles.empty?  
            log "file for images #{image_name} not found in #{image_path}"
          else
            num_images += 1
          end
        end
      else
        log "File #{image_desc_file} not found"
      end
    else
      log "Directory #{image_path} not found"
    end
    num_images
  end
  def add_variants(variants_file) 
    log " start adding variants"
    num_variants = 0
    File.open(variants_file).readlines[1..-1].each do |variant|
      v_info = {}
      variant_values = variant.split(ExportConfig::CSV_SEP)
      ExportConfig::VARIANT_HEADER.each_with_index do |label, i|
        v_info[label.to_sym] = variant_values[i]
      end
      next if v_info[:sku].nil? or v_info[:option_values].nil?
      num_variants += 1
      log "Read variant #{v_info[:sku]} of #{@product.sku} :" + v_info[:option_values]
      ot, val = v_info[:option_values].split(":")
      if ot.nil? or val.nil?
        log(" variant skipped: could not find ot or val?! check line format")
        next
      end
      opt_type = @product.option_types.select{|o| o.name == ot}.first # assume 1 
      opt_type = @product.option_types.create(:name => ot, :presentation => ot) if opt_type.nil?
      new_value = opt_type.option_values.create(:name => val, :presentation => val)
      ovariant = @product.variants.create(:sku => v_info[:sku])
      ovariant.count_on_hand = v_info[:count_on_hand] || 0
      ovariant.price = v_info[:price] unless v_info[:price].nil?
      ovariant.option_values << new_value
      ovariant.save!
      log(" variant priced #{ovariant.price} with sku #{ovariant.sku} saved for #{@product.sku}")
    end
    num_variants
  end
  def add_variant_images(variants_image_desc_file, image_path)
    log " start adding variants images"
    num_images = 0
    File.open(variants_image_desc_file).readlines[1..-1].each do |image_row|
      image_sku, image_name, alt_desc = image_row.chomp.split(":")
      next if image_sku.nil? or image_name.nil?
      num_images += 1
      imagefiles = Dir.new(image_path).entries.select{|f|f.include?(image_name)}
      if imagefiles.empty?  
        log "image #{image_name} present in alt-desc list,  not found in #{image_path}"
      else
        log "image #{image_name} present in alt-desc list,  found in #{image_path}"
        variants_found = @product.variants.select{|v|v.sku == image_sku}
        if variants_found.size == 0
          log " But No saved variant found with sku #{image_sku}, variant missing in variants.csv?"
          log " skipping image, because i cannot associate to any variant of the product :(", :warn
          next
        else
          log " #{variants_found.size} saved variants found with sku #{image_sku}, picking first"
        end
        image_variant = variants_found.first
        find_and_attach_image(File.join(image_path, image_name), image_variant, alt_desc)
        log("#{image_name} found for variant #{image_variant.sku} of #{@product.sku}")
      end
    end
    num_images
  end
end

class ProductUpload #< ActiveRecord::Base
  def self.upload_data(folder)
    begin
      m = UploadMonitor.new(folder)
      m.log "\n\n ******** Start Upload of #{folder} stuff *********\n"
      File.open(m.products_file).readlines[1..-1].each do |row|
        m.log "\n=== NEW PRODUCT ====="
        product_info = {}
        m.product = nil
        # stuff from the CSV
        next if row.strip.empty? # line is empty
        p = row.split(ExportConfig::CSV_SEP)
        ExportConfig::PROD_HEADER.each_with_index do |label, i|
          product_info[label.to_sym] = p[i]
          m.log "Read #{label} :" + product_info[label.to_sym]
        end
        # check that the sku is not taken!
        if m.check_sku_available(product_info[:sku]) #  the most important line of this code :)
          m.log "sku #{product_info[:sku]} available"
        else
          m.log "Product id (#{product_info[:sku]}) already taken !" 
          m.log "Jumping to next product :(", :warn
          next
        end
        # check that there are some images, no image? skip import of this product
        m.log "checking image path (just check how many exist, do not add yet)"
        image_path = File.join folder, product_info[:sku], ExportConfig::IMAGES_FOLDER
        num_images = m.check_image(image_path) 
        unless num_images > 0
          m.log "Jumping to next product :(", :warn
          next
        end
        m.log "#{num_images} available for the product"
        # end of image check
        # here we can create the product already 
        section = product_info.delete(:section)
        m.product = Product.new(product_info)
        unless m.product.valid?
          m.log("A product could not be imported, was not valid - :\n #{product_info.inspect}", :warn)
          next
        end
        #Save the object before creating asssociated objects 
        m.product.save
        m.log "basic product #{m.product.sku} was saved (no section, descs, details and variants added to it yet)"
        # associate taxa (brand and section)
        m.log "basic product #{m.product.sku}: try to associate section #{section} and brand #{m.brand} "
        if section.nil? or section.empty?
          m.log("No section (Productos) associated to this product", :warn)
        else
          category, subcategory = section.split("/")
          # Productos is the parent, taxon the category to which we attach
          m.associate_this_taxon(ExportConfig::SECTION_TAXON, category)
          # taxon is the parent, subtaxon the category to which we attach
          m.associate_subcategory(ExportConfig::SECTION_TAXON, category, subcategory) unless subcategory.empty?
        end
        m.associate_this_taxon(ExportConfig::BRAND_TAXON, m.brand)

        # now images (one single folder for all images including those from the variants)
        m.log "basic product #{m.product.sku}: try to add images (no variants images yet) "
        image_desc_file = File.join image_path, ExportConfig::IMAGES_DESC_FILE
        if File.exists?(image_desc_file)
          File.open(image_desc_file).readlines[1..-1].each do |image_row|
            image_sku, image_name, alt_desc = image_row.chomp.split(":")
            next if image_sku.nil? or image_name.nil?
            imagefiles = Dir.new(image_path).entries.select{|f|f.include?(image_name)}
            if imagefiles.empty?  
              m.log "file for images #{image_name} present in alt-desc list,  not found in #{image_path}"
            else
              m.find_and_attach_image(File.join(image_path, image_name), m.product, alt_desc)
            end
          end
        end
        m.log "basic product #{m.product.sku}: done with images (no variants images yet) "
        m.log "basic product #{m.product.sku}: jumping into my particular folder "
        # now stuff particular for the product
        product_folder = File.join(folder, m.product_folder)
        if File.exists?(product_folder)
          # desc
          m.log " Adding description "
          desc_file = File.join product_folder, ExportConfig::DESC_FILE
          m.product.description = File.open(desc_file).read if File.exists?(desc_file)
          m.log " description: #{m.product.description}"
          # meta desc
          m.log "basic product #{m.product.sku}: Adding meta-description "
          metadesc_file = File.join product_folder, ExportConfig::METADESC_FILE
          m.product.meta_description = File.open(metadesc_file).read if File.exists?(metadesc_file)
          m.log " meta-description: #{m.product.description}"
          # properties
          m.log "basic product #{m.product.sku}: Adding properties "
          prop_file = File.join product_folder, ExportConfig::PROPERTIES_FILE
          if File.exists?(prop_file)
            File.open(prop_file).readlines.each do |property|
              name, value = property.split(":")
              next if name.nil? or value.nil?
              m.find_and_assign_property_value(name, value)
              m.log " assigned property #{name} : #{value}"
            end
          end
          m.product.save
          m.log " product saved"
          # variants (we assume we work with a single option value / type per product)
          variants_file = File.join product_folder, ExportConfig::VARIANTS_FILE
          if File.exists?(variants_file)
            num_variants = m.add_variants(variants_file)
            m.log " tried to add #{num_variants} variants"
          end
          # images of the variants
          variants_image_desc_file = File.join image_path, ExportConfig::VARIANTS_IMAGES_DESC_FILE
          if File.exists?(variants_image_desc_file)
            num_images_variants = m.add_variant_images(variants_image_desc_file, image_path)
            m.log " tried to add #{num_images_variants} variant images"
          end
          m.log " done with product #{m.product.sku}"
        else
          m.log "No folder found for #{m.product_folder}"
        end
        m.log "Product  #{m.product.sku} was imported"
      end
      [:notice, "ran #{m.brand}, selected #{folder} at #{Time.now}"]
    rescue Exception => exp
      [:error, "error at #{Time.now}, #{exp.message}"]
    end
  end
end
