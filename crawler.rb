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
  puts "Creating table for titles"
  DB.exec("CREATE TABLE titles (id bigint, created_at timestamp default now(), title varchar(256), frontpage int default 0);")
rescue PG::DuplicateTable
  puts "Table already exists - fine"
end

def url_to_json(url)
  JSON.load(open(url).read)
end

def frontpage
  url_to_json(FRONTPAGE_URL).first(30)
end

def newstories
  url_to_json(NEWSTORIES_URL).first(20)
end

def story_title(id)
  url_to_json("https://hacker-news.firebaseio.com/v0/item/#{id}.json")['title']
end

# Grab new stories and save titles
news = newstories.map { |id| [id, story_title(id)] }

# Grab front page stories and save titles
fronts = frontpage.map { |id| [id, story_title(id)] }

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

DB.exec("UPDATE titles SET frontpage = 0")

# Any stories on the front page, mark as such
fronts.each do |(id, title)|
  DB.exec_params("UPDATE titles SET frontpage = 1 WHERE id = $1", [id.to_i])
end

results = DB.exec("select * from titles where id IN (select id from titles group by id having count(*) > 1) AND frontpage = 1 ORDER BY id DESC, created_at DESC;").to_a.group_by { |i| i["id"] }

puts "Uploading results to S3"
s3 = Aws::S3::Client.new
s3.put_object(bucket: ENV['S3_BUCKET'], key: "current.json", body: results.to_json, content_type: 'application/json')
s3.put_object_acl({ acl: "public-read", bucket: ENV['S3_BUCKET'], key: "current.json" })

puts "Triggering Netlify build hook"
`curl -X POST https://api.netlify.com/build_hooks/5c7583c5f27233a4701e6604`
