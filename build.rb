require 'erb'
require 'open-uri'
require 'json'

CACHE_FOLDER = "/opt/build/cache"

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

results = JSON.load(open('https://s3.amazonaws.com/jeanfromeastenders/current.json'))

out = ERB.new(template).result(binding)
File.open("_site/index.html", "w") { |f| f.puts out }

puts "Done"
