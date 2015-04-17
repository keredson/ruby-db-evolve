

class SQLColor

  BLACK = 30
  RED = 31
  GREEN = 32
  YELLOW = 33
  BLUE = 34
  MAGENTA = 35
  CYAN = 36
  WHITE = 37

  def self.colorize(sql)
    if sql.strip.start_with?('--')
      return apply(CYAN, sql)
    end
    sql = sql.gsub(/(ALTER|TABLE|COLUMN|ADD|TYPE|BEGIN|TRANSACTION|COMMIT)/){|s|apply(GREEN, s)}
    sql = sql.gsub(/(DROP)/){|s|apply(RED, s)}
    sql = sql.gsub(/("[^"]*")/){|s|apply(WHITE, s, bold=true)}
    return sql
  end

  def self.apply(color_code, text, bold=false)
    bold = bold ? ";1" : ""
    "\e[#{color_code}#{bold}m#{text}\e[0m"
  end

end



