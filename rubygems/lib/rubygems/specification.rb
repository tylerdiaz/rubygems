require 'date'

module Gem
  
  ##
  # == Gem::Platform
  #
  # Available list of platforms for targeting Gem installations.
  # Platform::RUBY is the default platform (pure Ruby Gem).
  #
  module Platform
    RUBY = 'ruby'
    WIN32 = 'mswin32'
    LINUX_586 = 'i586-linux'
    DARWIN = 'powerpc-darwin'
    CURRENT = 'current'
  end
  
  # Potentially raised when a specification is validated.
  class InvalidSpecificationException < Gem::Exception; end
  
  ##
  # == Gem::Specification
  #
  # The Specification class contains the metadata for a Gem.  Typically defined in a
  # .gemspec file or a Rakefile, and looks like this:
  #
  #   spec = Gem::Specification.new do |s|
  #     s.name = 'rfoo'
  #     s.version = '1.0'
  #     s.summary = 'Example gem specification'
  #     ...
  #   end
  #
  # There are many <em>gemspec attributes</em>, and the best place to learn about them in
  # the "Gemspec Reference" linked from the RubyGems wiki.
  #
  class Specification

    # ------------------------- Specification version contstants.

    # The the version number of a specification that does not specify one (i.e. RubyGems 0.7
    # or earlier).
    NONEXISTENT_SPECIFICATION_VERSION = -1

    # The specification version applied to any new Specification instances created.  This
    # should be bumped whenever something in the spec format changes.
    CURRENT_SPECIFICATION_VERSION = 1

    # An informal list of changes to the specification.  The highest-valued key should be
    # equal to the CURRENT_SPECIFICATION_VERSION.
    SPECIFICATION_VERSION_HISTORY = {
      -1 => ['(RubyGems versions up to and including 0.7 did not have versioned specifications)'],
      1  => [
        'Deprecated "test_suite_file" in favor of the new, but equivalent, "test_files"',
        '"test_file=x" is a shortcut for "test_files=[x]"',
        'Introduced "library_stubs" attribute, to allow the creation of several library stubs'
      ]
    }

    # ------------------------- Class variables.

    # List of Specification instances.
    @@list = []
    # List of attribute names: [:name, :version, ...]
    @@required_attributes = []
    # List of _all_ attributes and default values: [[:name, nil], [:bindir, 'bin'], ...]
    @@attributes = []
    
    # ------------------------- Class methods.

    # A list of Specification instances that have been defined in this Ruby instance.
    def self.list
      @@list
    end

    # Used to specify the name and default value of a specification attribute.
    def self.attribute(name, default=nil)
      @@attributes << [name, default]
      attr_accessor(name)
    end

    # Same as attribute above, but also records this attribute as mandatory.
    def self.required_attribute(*args)
      @@required_attributes << args.first
      attribute(*args)
    end

    # Sometimes we don't want the world to use a setter method for a particular attribute.
    # +read_only+ makes it private so we can still use it internally.
    def self.read_only(*names)
      names.each do |name|
        private "#{name}="
      end
    end

    # Shortcut for creating several attributes at once (each with a default value of
    # +nil+).  Called _without_ any arguments, returns a list of all attribute names. 
    def self.attributes(*args)
      if args.empty? then return @@attributes.map { |name, default| name } end
      args.each do |arg|
        attribute(arg, nil)
      end
    end

    # Some attributes require special behaviour when they are accessed.  This allows for
    # that.
    def self.overwrite_accessor(name, &block)
      remove_method name
      define_method(name, &block)
    end

    ##
    # Defines a _singular_ version of an existing _plural_ attribute (i.e. one whose value
    # is expected to be an array).  This means just creating a helper method that takes a
    # single value and appends it to the array.  These are created for convenience, so
    # that in a spec, one can write
    #
    #   s.require_path = 'mylib'
    #
    # instead of
    #
    #   s.require_paths = ['mylib']
    #
    # That above convenience is available courtesy of
    #
    #   attribute_alias_singular :require_path, :require_paths 
    #
    def self.attribute_alias_singular(singular, plural)
      define_method("#{singular}=") { |val|
        send("#{plural}=", [val])
      }
    end

    def warn_deprecated(old, new)
      # How (if at all) to implement this?  We only want to warn when a gem is being
      # built, I should think.
    end
    
    # ------------------------- REQUIRED gemspec attributes.
    
    required_attribute :rubygems_version, RubyGemsVersion
    required_attribute :specification_version, CURRENT_SPECIFICATION_VERSION
    required_attribute :name
    required_attribute :version
    required_attribute :date
    required_attribute :summary
    required_attribute :require_paths, ['lib']
    
    read_only :specification_version

    # ------------------------- OPTIONAL gemspec attributes.
    
    attributes :author, :email, :homepage, :rubyforge_project, :description
    attributes :autorequire, :default_executable
    attribute :bindir,                'bin'
    attribute :has_rdoc,               false
    attribute :required_ruby_version, '> 0.0.0'
    attribute :platform,               Gem::Platform::RUBY
    attribute :files,                  []
    attribute :test_files,             []
    attribute :library_stubs,          []
    attribute :rdoc_options,           []
    attribute :extra_rdoc_files,       []
    attribute :executables,            []
    attribute :extensions,             []
    attribute :requirements,           []
    attribute :dependencies,           []

    read_only :dependencies

    # ------------------------- ALIASED gemspec attributes.
    
    attribute_alias_singular :executable,   :executables
    attribute_alias_singular :require_path, :require_paths
    attribute_alias_singular :test_file,    :test_files

    # ------------------------- DEPRECATED gemspec attributes.
    
    def test_suite_file
      warn_deprecated(:test_suite_file, :test_files)
      @test_files.first
    end

    def test_suite_file=(val)
      warn_deprecated(:test_suite_file, :test_files)
      @test_files << val
    end
 
    # ------------------------- RUNTIME attributes (not persisted).
    
    attr_writer :loaded, :loaded_from

    # ------------------------- Special accessor behaviours (overwriting default).
    
    overwrite_accessor :version= do |version|
      unless version.nil?
        unless version.respond_to? :version
          version = Version.new(version)
        end
      end
      @version = version
    end

    overwrite_accessor :platform= do |platform|
      # Checks the provided platform for Platform::CURRENT and changes
      # it to be binary specific to the current platform (i383-mswin32, etc).
      #
      # XXX: does this method do as the comment says? 
      @platform = (platform == Platform::CURRENT ? RUBY_PLATFORM : platform)
    end

    overwrite_accessor :required_ruby_version= do |version|
      @required_ruby_version = Gem::Version::Requirement.new(version)
    end

    overwrite_accessor :date= do |date|
      # We want to end up with a Date object.  If _date_ responds to :to_str, or :day,
      # :month, and :year, it is duly converted.  Otherwise, today's date is used. 
      if date.respond_to? :to_str
        date = Date.parse(date.to_str)
      elsif [:year, :month, :day].all? { |m| date.respond_to? m }
        date = Date.new(date.year, date.month, date.day)
      else
        date = nil
      end
      @date = date || Date.today
    end

    overwrite_accessor :summary= do |str|
      if str
        @summary = str.strip.gsub(/(\w-)\n[ \t]*(\w)/, '\1\2').gsub(/\n[ \t]*/, " ")
      end
    end

    overwrite_accessor :description= do |str|
      if str
        @description = str.strip.gsub(/(\w-)\n[ \t]*(\w)/, '\1\2').gsub(/\n[ \t]*/, " ")
      end
    end

    overwrite_accessor :default_executable do
      return @default_executable if @default_executable
      # Special case: if there is only one executable specified, then that's obviously the
      # default one.
      return @executables.first if @executables.size == 1
      nil
    end

    # ------------------------- Predicates.
    
    def loaded?; @loaded ? true : false ; end
    def has_rdoc?; @has_rdoc ? true : false ; end
    def has_unit_tests?; not @test_files.empty?; end
    alias has_test_suite? has_unit_tests?               # (deprecated)
    
    # ------------------------- Constructor.
    
    ##
    # Specification constructor.  Assigns the default values to the attributes, adds this
    # spec to the list of loaded specs (see Specification.list), and yields itself for
    # further initialization.
    #
    def initialize
      @@attributes.each do |name, default|
        self.send "#{name}=", _copy(default)
      end
      @loaded = false
      @@list << self
      yield self if block_given?
    end
    
    # ------------------------- Instance methods.
    
    ##
    # Sets the rubygems_version to Gem::RubyGemsVersion.
    #
    def mark_version
      @rubygems_version = RubyGemsVersion
    end

    ##
    # Adds a dependency to this Gem.  For example,
    #
    #   spec.add_dependency('jabber4r', '> 0.1', '<= 0.5')
    #
    # gem:: [String or Gem::Dependency] The Gem name/dependency.
    # requirements:: [default="> 0.0.0"] The version requirements.
    #
    def add_dependency(gem, *requirements)
      requirements = ['> 0.0.0'] if requirements.empty?
      requirements.flatten!
      unless gem.respond_to?(:name) && gem.respond_to?(:version_requirements)
        gem = Dependency.new(gem, requirements)
      end
      dependencies << gem
    end
    
    ##
    # Returns the full name (name-version) of this Gem.  Platform information is included
    # (name-version-platform) if it is specified (and not the default Ruby platform).
    #
    def full_name
      if @platform.nil? or @platform == Gem::Platform::RUBY
        "#{@name}-#{@version}"
      else
        "#{@name}-#{@version}-#{@platform}"
      end 
    end
    
    ##
    # The full path to the gem (install path + full name).
    #
    # return:: [String] the full gem path
    #
    def full_gem_path
      File.join(installation_path, "gems", full_name)
    end
    
    ##
    # The root directory that the gem was installed into.
    #
    # return:: [String] the installation path
    #
    def installation_path
      (File.dirname(@loaded_from).split(File::SEPARATOR)[0..-2]).join(File::SEPARATOR)
    end
    
    ##
    # Checks if this Specification meets the requirement of the supplied
    # dependency.
    # 
    # dependency:: [Gem::Dependency] the dependency to check
    # return:: [Boolean] true if dependency is met, otherwise false
    #
    def satisfies_requirement?(dependency)
      return @name == dependency.name && 
        dependency.version_requirements.satisfied_by?(@version)
    end
    
    # ------------------------- Comparison methods.
    
    ##
    # Compare specs (name then version).
    #
    def <=>(other)
      [@name, @version] <=> [other.name, other.version]
    end

    # Tests specs for equality (across all attributes).
    def ==(other)
      @@attributes.each do |name, default|
        return false unless self.send(name) == other.send(name)
      end
      true
    end
    
    # ------------------------- Export methods (YAML and Ruby code).
    
    # Returns an array of attribute names to be used when generating a YAML representation
    # of this object.  If an attribute still has its default value, it is omitted.
    def to_yaml_properties
      mark_version
      @@attributes.map { |name, default| "@#{name}" }
    end

    # Returns a Ruby code representation of this specification, such that it can be
    # eval'ed and reconstruct the same specification later.  Attributes that still have
    # their default values are omitted.
    def to_ruby
      mark_version
      result = "Gem::Specification.new do |s|\n"
      @@attributes.each do |name, default|
        next if name == :dependencies
        current_value = instance_variable_get "@#{name}"
        result << "  s.#{name} = #{_ruby_code(current_value)}\n" unless current_value == default
      end
      @dependencies.each do |dep|
        version_reqs_param = dep.requirements_list.inspect
        result << "  s.add_dependency(%q<#{dep.name}>, #{version_reqs_param})\n"
      end
      result << "end\n"
    end

    # ------------------------- Validation and normalization methods.
    
    ##
    # Checks that the specification contains all required fields, and
    # does a very basic sanity check.
    #
    # Raises InvalidSpecificationException if the spec does not pass
    # the checks..
    def validate
      normalize
      if @rubygems_version != RubyGemsVersion
        raise InvalidSpecificationException.new(%[
          Expected RubyGems Version #{RubyGemsVersion}, was #{@rubygems_version}
        ].strip)
      end
      @@required_attributes.each do |symbol|
        unless self.send(symbol)
          raise InvalidSpecificationException.new("Missing value for attribute #{symbol}")
        end
      end 
      if @require_paths.empty?
        raise InvalidSpecificationException.new("Gem spec needs to have at least one require_path")
      end
    end

    ##
    # Normalize the list of files so that:
    # * All file lists have redundancies removed.
    # * Files referenced in the extra_rdoc_files are included in the package file list.
    #
    # Also, the summary and description are converted to a normal format.
    def normalize
      if @extra_rdoc_files
        @extra_rdoc_files.uniq!
        @files ||= []
        @files.concat(@extra_rdoc_files)
      end
      @files.uniq! if @files
    end

    # ------------------------- Dependency methods.
    
    ##
    # return:: [Array] [[dependent_gem, dependency, [list_of_satisfiers]]]
    #
    def dependent_gems
      out = []
      Gem.cache.each do |name,gem|
        gem.dependencies.each do |dep|
          if self.satisfies_requirement?(dep) then
            sats = []
            _find_all_satisfiers(dep) do |sat|
              sats << sat
            end
            out << [gem, dep, sats]
          end
        end
      end
      out
    end

    private

    def _find_all_satisfiers(dep)
      Gem.cache.each do |name,gem|
        if(gem.satisfies_requirement?(dep)) then
          yield gem
        end
      end
    end

    # Duplicate an object unless it's an immediate value.
    def _copy(obj)
      case obj
      when Numeric, Symbol, true, false, nil then obj
      else obj.dup
      end
    end

    # Return a string containing a Ruby code representation of the given object.
    def _ruby_code(obj)
      case obj
      when String       then '%q{' + obj + '}'
      when Array        then obj.inspect
      when Gem::Version then obj.to_s.inspect
      when Date         then '%q{' + obj.strftime + '}'
      end
    end

  end  # class Specification
end  # module Gem

