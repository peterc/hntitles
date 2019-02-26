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
  DB.exec("CREATE TABLE titles (id bigint, created_at timestamp default now(), title varchar(256));")
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

#puts "---\nRESULTS:\n\n"
#p DB.exec("SELECT * FROM titles").to_a

# select * from titles where id = (select id from titles group by id having count(*) > 1);
# select * from titles where id IN (select id from titles group by id having count(*) > 1) ORDER BY id DESC, created_at DESC;
