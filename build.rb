require 'erb'
require 'pg'
require 'dotenv'

Dotenv.load
CACHE_FOLDER = "/opt/build/cache"
DB = PG.connect(ENV['POSTGRES_URL'])

if Dir.exist?("_site")
  puts "Deleting any build artefacts"
  `rm -f _site/*`  
else
  puts "Making build directory"
  Dir.mkdir("_site") 
end

puts "Copying static files to build directory"
`cp site/* _site/`

puts "Rendering dynamic stuff"

template = File.read(__dir__ + "/site/index.html")
results = DB.exec("select * from titles where id IN (select id from titles group by id having count(*) > 1) ORDER BY id DESC, created_at ASC;")

results = results.to_a.group_by { |item| item['id'] }


out = ERB.new(template).result(binding)
File.open("_site/index.html", "w") { |f| f.puts out }

puts "Done"
