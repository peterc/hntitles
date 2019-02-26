require 'aws-sdk'
require 'open-uri'
require 'json'
require 'pg'
require 'dotenv'

Dotenv.load

FRONTPAGE_URL = "https://hacker-news.firebaseio.com/v0/topstories.json"
NEWSTORIES_URL = "https://hacker-news.firebaseio.com/v0/newstories.json"

DB = PG.connect(ENV['POSTGRES_URL'])

begin
  puts "Creating table for storing titles"
  DB.exec("CREATE TABLE titles (id bigint, created_at timestamp default now(), title varchar(256), frontpage int default 0);")
rescue PG::DuplicateTable
  puts "Table already exists - fine"
end

def url_to_json(url)
  JSON.load(open(url).read)
end

def story_title(id)
  url_to_json("https://hacker-news.firebaseio.com/v0/item/#{id}.json")['title']
end

# Grab new stories and save titles
news = url_to_json(NEWSTORIES_URL).first(20).map { |id| [id, story_title(id)] }

# Grab front page stories and save titles
fronts = url_to_json(FRONTPAGE_URL).first(30).map { |id| [id, story_title(id)] }

# Go through all the items and process accordingly
(news + fronts).each do |(id, title)|
  puts "#{id}-#{title}"

  res = DB.exec_params("SELECT title FROM titles WHERE id = $1 ORDER BY created_at DESC LIMIT 1", [id.to_i])

  if res.to_a == []
    # No matches, so let's add to database
    DB.exec_params("INSERT INTO titles (id, title) VALUES ($1, $2)", [id.to_i, title.to_s])
    puts "  -> ADDING"
  elsif res.to_a[0]['title'] != title.to_s
    # The title does not match with the last scanned one, it's changed!
    DB.exec_params("INSERT INTO titles (id, title) VALUES ($1, $2)", [id.to_i, title.to_s])
    puts "  -> CHANGED!!!"
  else
    # Otherwise, do nothing.. title has not changed!
    puts "  -> NO CHANGE"
  end
end

# Uncomment this if you ONLY want CURRENT frontpage items marked as such
# DB.exec("UPDATE titles SET frontpage = 0")

# Any stories on the front page, mark as such
fronts.each do |(id, title)|
  DB.exec_params("UPDATE titles SET frontpage = 1 WHERE id = $1", [id.to_i])
end

if ENV['S3_BUCKET']
  puts "Uploading results to S3"

  results = DB.exec("select * from titles where id IN
    (select id from titles where frontpage = 1 group by id having count(*) > 1 order by id desc limit 50)
    ORDER BY id DESC, created_at DESC;").to_a.group_by { |i| i["id"] }
  
  s3 = Aws::S3::Client.new
  s3.put_object(bucket: ENV['S3_BUCKET'], key: "current.json", body: results.to_json, content_type: 'application/json')
  s3.put_object_acl({ acl: "public-read", bucket: ENV['S3_BUCKET'], key: "current.json" })
end

if ENV['NETLIFY_WEBHOOK']
  puts "Triggering Netlify build hook"
  `curl -X POST -d {} #{ENV['NETLIFY_WEBHOOK']}`
end