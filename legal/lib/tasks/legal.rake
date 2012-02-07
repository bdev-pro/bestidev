# add custom rake tasks here
task :list_mails => :environment do
  puts "emails"
  puts Order.all.map{|o| o.email}.uniq.join(",")
end



