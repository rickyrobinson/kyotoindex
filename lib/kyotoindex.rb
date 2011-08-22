require 'kyototycoon'
require 'kyotoindex/search'
module KyotoIndex
  
        DEFAULT_STOP_WORDS = %(a able about across after all almost also am among an and any are as at be because been but by can cannot could dear did do does either else ever every for from get got had has have he her hers him his how however i if in into is it its just least let like likely may me might most must my neither no nor not of off often on only or other our own rather said say says she should since so some than that the their them then there these they this tis to too twas us wants was we were what when where which while who whom why will with would yet you your)
  
  mattr_accessor :databases, :stopwords
  @@databases = {}
  @@stopwords = DEFAULT_STOP_WORDS

  def self.setup(&block)
    yield self
    add_db :default unless @@databases[:default]
    set_meta_db :default unless @@databases[:meta]
  end

  def self.add_db name, options={}
    KyotoTycoon.configure(name) do |kt|
      kt.db = options[:db] || '*'
    end

    kt = KyotoTycoon.create(name)
    kt.serializer = options[:serializer] || :default

    @@databases[name] = kt
    kt
  end
  
  def self.set_default_db name, options={}
    @@databases[:default] = @@databases[name] || add_db(name, options)
  end
  
  def self.set_meta_db name, options={}
    @@databases[:meta] = @@databases[name] || add_db(name, options)
  end
  
  def self.set_stopwords stopwords
    @@stopwords = stopwords
  end
end
