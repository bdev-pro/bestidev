class Admin::ProductExportController < Admin::BaseController
  def index
    redirect_to :action => :new
  end
  
  def new
    @product_export = ProductExport.new
  end
  
  def create
    h, export_results = ProductExport.export_data
    flash[h] = export_results
    render :new
  end

end
