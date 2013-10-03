require 'rubygems'
require 'debugger'
require 'neography'

class WordNet
  attr_accessor :neo

  PTR_RELATIONSHIP = {
    '!' => :is_antonym,
    '@' => :is_hypernym,
    '@!' => :is_instance_hypernym,
    '~' => :is_hyponym,
    '~i' => :is_instance_hyponym,
    '#m' => :is_member_holonym,
    '#s' => :is_substance_holonym,
    '#p' => :is_part_holonym,
    '%m' => :is_member_meronym,
    '%s' => :is_substance_meronym,
    '%p' => :is_part_meronym,
    '=' => :is_attribute,
    '+' => :is_derivationally_related_from,
    ';c' => :is_domain_of_synset_topic,
    '-c' => :is_member_of_this_domain_topic,
    ';r' => :is_domain_of_synset_region,
    '-r' => :is_member_of_this_synset_region,
    ';u' => :is_domain_of_synset_usage,
    '-u' => :is_member_of_this_synset_usage
  }

  DATAFILE_LIST = %w(data.noun)

  def initialize(options = {})
    puts "Configuring Neo4j database..."

    Neography.configure do |config|
      config.protocol       = "http://"
      config.server         = "localhost"
      config.port           = 7474
      config.directory      = ""  # prefix this path with '/'
      config.cypher_path    = "/cypher"
      config.gremlin_path   = "/ext/GremlinPlugin/graphdb/execute_script"
      config.log_file       = "neography.log"
      config.log_enabled    = false
      config.max_threads    = 20
      config.authentication = nil  # 'basic' or 'digest'
      config.username       = nil
      config.password       = nil
    end

    dict_path = options[:data_path]

    DATAFILE_LIST.each { |datafile| process_datafile("#{dict_path}/#{datafile}") }
  end

  def neo
    @neo ||= Neography::Rest.new
  end

private
  SynsetRelation = Struct.new(:type, :src_index, :dest_index, :parts_of_speech)

  def process_datafile(filename)
    synset_relations = []
    node_index = {}

    nodes_created = 0
    File.open(filename).each do |line|
      if part_of_liscense?(line)
        puts "Skipping following line: #{line}"
        next
      end

      parts = line.split(' ')

      synset_index = parts.shift
      lexname      = parts.shift
      synset_type  = parts.shift
      word_count   = parts.shift

      words = []
      word_count.to_i.times do
        words << parts.shift
        parts.shift
      end
      name         = words.first

      related_synset_count = parts.shift
      related_synset_count.to_i.times do
        relation_type = parts.shift
        related_synset_index = parts.shift
        pos = parts.shift # parts-of-speech

        synset_relations << SynsetRelation.new(
          PTR_RELATIONSHIP[relation_type],
          synset_index,
          related_synset_index,
          pos
        )

        # Don't care about this data piece
        parts.shift
      end

      node_index[synset_index] = neo.create_node(
        lexname: lexname,
        synset_type: synset_type,
        word_count: word_count,
        name: name
      )

      nodes_created += 1
      puts "#{nodes_created} nodes created..." if nodes_created % 1000 == 0
    end

    relations_created = 0
    synset_relations.each do |relation|
      src_node = node_index[relation.src_index]
      dest_node = node_index[relation.dest_index]

      if !src_node
        puts "ERROR: source node doesn't exist!"
      elsif !dest_node
        puts "ERROR: destination node doesn't exist!"
      elsif !relation.type
        puts "ERROR: unknown relationship type!"
      else
        begin
          neo.create_relationship(
            relation.type,
            src_node,
            dest_node
          )

          relations_created += 1
          puts "#{relations_created} relations created..." if relations_created % 1000 == 0
        rescue Neography::NeographyError => e
          puts "ERROR: unknown error occurred!"
        end
      end
    end
  end

  def part_of_liscense?(line)
    line.start_with?('  ')
  end
end

WordNet.new(data_path: 'wordnet-3.0/dict')
