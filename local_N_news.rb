require 'slop'
require './helpers'
require 'ddr-antivirus'
require 'fileutils'
require 'bagit'
require 'net/sftp'
require 'optparse'



def antivirus_scan(dir)
  Ddr::Antivirus.scanner_adapter = :clamd # need to be update
  result = Ddr::Antivirus.scan dir
end

def generate_filelist(dir, file_list)
  begin
    if File.directory?(dir)
      DirToXml.dir2list(dir, file_list)
    else
      raise 'Invalid Directory'
    end
  rescue Exception => e
    puts "Error in generating list of files"
    puts e.message
    logger.error e.message
    logger.error e.backtrace.inspect
  end
end

def create_bag(target_dir, files, full_path)
  bag = BagIt::Bag.new target_dir
  files.each do |f|
    File.open(f) do |rio|
      if full_path
        file_path = f.gsub!(/[^0-9A-Za-z.\-]/, '_')
      else
        file_path = File.basename(f)
      end
        begin
          bag.add_file(file_path) {|io| io.write rio.read }
        rescue Exception => e
          cleanup(target_dir)
          retry
       end
    end
  end
  bag.manifest!
end

def validate_bag(dir)
  bag = BagIt::Bag.new dir
  return bag.valid?
end

def mysql_query(connection,query)
  begin
    rs = connection.query(query)
  rescue Exception => e
    raise e
    raise e if /Mysql::Error: Duplicate entry/.match(e.to_s)
  end
end

def ingest_files(issue_path, saved_location, file_type)
  target_dir = File.join(saved_location, file_type.upcase)
  FileUtils::mkdir_p target_dir
  issue = issue_path.split("/").last
  case file_type
  when "pdf", "jp2"
    files = Dir.glob(issue_path+"/**/*."+file_type.downcase)
  when "tiff"
    files = Dir.glob(issue_path+"**/*.tif")
  when "alto"
    #files = Dir.glob(issue_path+"**/ALTO/*.xml")
    #files = Dir.glob(issue_path+"/**/.....xml")
    files = Dir.glob(issue_path+'**/*.xml').grep(/[^METS].xml/)
  when "mets"
    #files = Dir.glob(issue_path+'**/*.xml').grep(/[^\/\d\d\d\d\.xml]/)
    files = Dir.glob(issue_path+"/**/*METS.xml")
  end
  create_bag(target_dir, files, false)
  Utils.tar(File.join(saved_location, "#{file_type.downcase}.tar"), "#{target_dir}")
  #delete untar file
  FileUtils.rm_rf(target_dir)
  #create md5 for each file in a folder
  DirToXml.generatemd5(saved_location)
end





def cleanup(dir)
  FileUtils.rm_rf(dir)
end


def newspaper(opts, mysql_connection)
  dir = opts[:directory]
  puts dir
  publication = opts[:publication]
  delivery = opts[:delivery]
  drive_id = opts[:drive_id]
  dryrun = opts[:dryrun]
  Dir.glob("#{dir}/**/*METS.xml") do |f|
    #puts f
    issue_path = File.dirname(f)
    puts issue_path
    issue = issue_path.split("/").last
    #puts issue
    publication=issue[0,3]
    puts publication
    year = issue[4,4]
    month = issue[8,2]
    date = issue[10,2]
    edition = '01'
    puts year
    puts month
    puts date
    puts edition
    pagecount = Dir.glob("#{issue_path}/*.jp2").count
    insert = "INSERT INTO newspapers(newspaper, year, month, day, edition, pages, delivery, delivery_disk, delivery_date) VALUES ('#{publication}', #{year}, #{month}, #{date}, #{edition}, #{pagecount}, '#{delivery}', '#{drive_id}', NOW()) ON DUPLICATE KEY UPDATE  pages = VALUES(pages), delivery = VALUES(delivery), delivery_disk = VALUES(delivery_disk), delivery_date = VALUES(delivery_date) "
    puts insert
    temp_dir = 'upload_news3'
    temp_location = File.join(temp_dir, "#{issue}"+"#{edition}")
    puts temp_location
    puts "---------------------------------"
    ingest_files(issue_path, temp_location, 'jp2') if Dir.glob("#{issue_path}/**/*.jp2").count > 0
#     ingest_files(issue_path, temp_location, 'tiff') if Dir.glob("#{issue_path}/**/*.tif").count > 0
    ingest_files(issue_path, temp_location, 'alto')
    ingest_files(issue_path, temp_location, 'mets')
    ingest_files(issue_path, temp_location, 'pdf') if Dir.glob("#{issue_path}/**/*.pdf").count > 0
    File.open(File.join(temp_location,'insert.txt'), 'w') { |file| file.write(insert) }
    noid = Utils.noid
    metadata = {"publication" => publication, "year"=> year, "month" => month, "date" => date, "noid" => noid }
    File.open(File.join(temp_location,'metadata.marshal'), "w"){|to_file| Marshal.dump(metadata, to_file)}
    update = "UPDATE newspapers set noid = '#{noid}' where newspaper = '#{publication}' and year = '#{year}' and month = '#{month}' and day = '#{date}' and edition=1"
    #write into a file instead of execute in the database
    File.open(File.join(temp_location,'update.txt'), 'w') { |file| file.write(update) }
#
 end
end




  options = {}
  OptionParser.new do |opts|
    opts.on("-t", "--resource-type TYPE", "Type of resource is to be ingested (peelbib,newspaper, image, steele, other)") do |v|
      options[:resource_type] = v
    end
    opts.on("-r", "--[no-]dry-run", "Dry run of the ingest") do |v|
      options[:dry_run] = v
    end
    opts.on("-f", "--directory FOLDER", "Directory that need to be ingested") do |v|
      options[:directory] = v
    end
    opts.on("-l", "--file-list LIST", "File name of the file list output") do |v|
      options[:file_list] = v
    end
    opts.on("-d", "--delivery DELIVERY", "Delivery number that this ingest batch will be logged in the database") do |v|
      options[:delivery] = v
    end
    opts.on("-i", "--drive-id ID", "last four digits of the hard drive ID this delivery is on") do |v|
      options[:drive_id] = v
    end
    opts.on("-p", "--publication PUB", "Three digit publication code for newspaper and magazine") do |v|
      options[:publication] = v
    end
    opts.on("-c", "--collection COLL", "Collection name that this ingest batch belongs to") do |v|
      options[:collection] = v
    end
    opts.on("-b", "--[no-]skipbag", "Skip checking if the delivery is a valid bag") do |v|
      options[:skipbag] = v
    end
  end.parse!
  p options
  timestamp = Time.now.to_s.tr(" ", "_")
  dir = options[:directory]
  file_list = options[:file_list]
  last_dir = dir.split("/").last
  type = options[:resource_type]
  dryrun = options[:dry_run]
  collection = options[:collection]
  skip_bag = options[:skipbag]
  logfile = "log/local-#{last_dir}-#{timestamp}"
  logger = Logger.new(logfile)
  logger.info "Start Ingest the directory #{dir}"
  # #Virus Scanning
  # logger.info "Start scanning the directory for virus"
  # scan_result = antivirus_scan(dir)
  # logger.info "Virus scanning completed, at #{scan_result.scanned_at}"
  # logger.info scan_result.to_s
  # #Generating filelist
  # logger.info "Generating list of files within the directory #{dir}"
  # generate_filelist(dir, file_list)
  # valid = DirToXml.validation(dir, file_list)
  # logger.info "Successfully generated a file list at #{file_list}" if valid
  # puts "xml correct" if valid
  # logger.error "Error when creating file list for #{dir}" if !valid
  # puts "xml wrong" if !valid
  # #Validate bag
  # unless skip_bag
  #   logger.info "Start to valid bags in the delivery"
  #   bagcount = Dir.glob(dir+"/**/bagit.txt").count
  #   logger.info "Validate #{bagcount} bag directories in the delivery"
  #   validate_bag(dir)
  #   Dir.glob(dir+"/**/bagit.txt") do |f|
  #     d = File.dirname(f)
  #     bag_valid = validate_bag(d)
  #     if bag_valid
  #       logger.info "Directory #{d} is a valid bag"
  #       FileUtils.touch (d +'/bag_verified')
  #     else
  #       logger.error "Directory #{d} is not a valid bag, view log files for more detailed information"
  #       FileUtils.touch (d+'/bag_not_verified')
  #     end
  #   end
  #   puts "bag finish"
  # end
  #Checkin to the database
  logger.info "Checkin the delivery into the tracking database"
  connection = Helpers.set_mysql_connection
  if type == "newspaper"
    newspaper(options, connection)
  elsif type == "peel"
    peel(options,connection)
  elsif type == "steele"
    steele(options,connection)
  elsif type == "generic"
    generic(options, connection)
  end
  Helpers.close_mysql_connection(connection)
  # #Upload to jeoffry
  # Net::SFTP.start('jeoffry.library.ualberta.ca', 'baihong', :password => '100ofrainbows') do |sftp|
  #   # upload a file or directory to the remote host
  #   if sftp.upload!("/home/baihong/peel-scripts-ruby/upload", "/var/peel-scripts-ruby/upload")
  #     puts "upload Finish"
  #   end
  # end