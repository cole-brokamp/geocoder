require 'rubygems'
require 'geo_ruby'
require 'zip/zip'
require 'tmpdir'
require 'find'

module Geocoder
end

module Geocoder::US
end


module Geocoder::US::Tiger
  class Cache
    attr :face2place
    attr :line2place
    attr :line2zip
    attr :tlids

    def reset!
      @face2place = {}
      @line2place = {}
      @line2zip   = {}
      @tlids      = {}
    end
    
    alias initialize reset!
  end

  class Shp
    attr :cache
    def initialize (filename, cache=nil)
      cache = Cache.new() if cache.nil?
      @shp = GeoRuby::Shp4r::ShpFile.open(filename + "_" + self.class.suffix)
      @cache = cache
    end
    def each
      @shp.each {|record| 
        add_to_cache record.data
        yield record
      }
    end
    def add_to_cache (record)
    end
  end

  class Dbf < Shp
    def initialize (filename, cache=nil)
      cache = Cache.new() if cache.nil?
      filename += "_" + self.class.suffix + ".dbf"
      @dbf = GeoRuby::Shp4r::Dbf::Reader.open(filename)
      @cache = cache
    end
    def record (idx)
      @dbf.record(idx)
    end
    def each
      for i in 0 ... @dbf.record_count
        record = @dbf.record(i)
        add_to_cache record
        yield GeoRuby::Shp4r::ShpRecord.new(nil,record)
      end
    end
  end

  class CurrentPlaces < Dbf
    def self.suffix
      "place"
    end    
  end

  class AllLines < Shp
    def self.suffix
      "edges"
    end
    def add_to_cache(record)
      @cache.line2place[record["TLID"]] = [
        @cache.face2place[record["TFIDL"]], 
        @cache.face2place[record["TFIDR"]]
      ]
      @cache.line2zip[record["TLID"]] = [
        record["ZIPL"],
        record["ZIPR"]  
      ] 
    end
  end

  class AddressRanges < Dbf
    def self.suffix
      "addr"
    end
    def add_to_cache(record)
      @cache.tlids[record["TLID"]] = true
    end
  end

  class FeatureNames < Dbf
    def self.suffix
      "featnames"
    end
  end 

  class TopoFaces < Dbf
    def self.suffix
      "faces"
    end
    def add_to_cache(record)
      @cache.face2place[record["TFID"]] = record["STATEFP"]+record["PLACEFP"]
    end
  end

  class State
    def initialize (path)
      @path = path
    end
    def import_file (cls, db)
      archive, = Dir["#{@path}/*_#{cls.suffix}.zip"]
      throw "can't find #{cls.suffix} ZIP file in #{@path}" if archive.nil?
      Dir.mktmpdir {|dir|
        Zip::ZipFile::open(archive) { |zf|
           zf.each {|file| zf.extract(file, File.join(dir, file.name)) }
        } 
        archive[/_[a-z]+\.zip$/] = ""
        extracted = File.join(dir, File.basename(archive))
        source = cls.new(extracted, @cache)
        db.import_all(source)
      }
    end
    def import (db)
      puts "importing places from " + @path
      import_file(CurrentPlaces, db)
      Find.find(@path) {|dir|
        County.new(dir).import(db) if dir != @path and File.directory? dir
      }
    end
  end

  class County < State
    def initialize (path)
      @path = path
      @cache = Cache.new()
    end
    def import (db)
        puts "importing " + @path
        for cls in [TopoFaces, AddressRanges, AllLines, FeatureNames]
          puts "  loading " + cls.suffix
          import_file(cls, db)
        end
    end
  end

  def import (path)

  end
end