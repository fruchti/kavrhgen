#!/usr/bin/ruby

# KICAD NETLIST AVR C HEADER FILE GENERATOR
# -fruchti 2015

require 'optparse'
require 'fileutils'
require 'pathname'
require 'yaml'

options = Hash.new()
config = Hash.new()

# Gives the #define names in case multiple pins are connected to one signal
def disambiguate(signal, number, pin)
    return signal + '_' + ('A' .. 'Z').to_a()[number]
end

# Escape the string from the KiCAD netlist so it can be written into the header
def escape(signal, config)
    signal.gsub!('~', config['InvertSymbol'])
    if config['Capitalize']
        signal.upcase!
    end
    return signal
end

# Write the defines for one pin
def define(signal, pin, config)
    port = pin.match(/P([A-Z])/)[1].upcase
    pinnum = pin.match(/P[A-Z]([0-7])/)[1]
    d_bit = escape(sprintf(config['BitFormat'], signal), config)
    d_ddr = escape(sprintf(config['DDRFormat'], signal), config)
    d_port = escape(sprintf(config['PORTFormat'], signal), config)
    d_pin = escape(sprintf(config['PINFormat'], signal), config)
    define = ''
    if config['UseBitMasks']
        define += sprintf("#define %-31s %-11s // %s\n", d_bit, '(1 << ' + pinnum + ')', pin)
    else
        define += sprintf("#define %-31s %-11s // %s\n", d_bit, pinnum, pin)
    end
    define += sprintf("#define %-31s %-11s // \n", d_ddr, 'DDR' + port)
    define += sprintf("#define %-31s %-11s // \n", d_port, 'PORT' + port)
    define += sprintf("#define %-31s %-11s // \n", d_pin, 'PIN' + port)
    return define
end

# Escapes the filename for the #ifndef/#define stuff
def escape_filename(filename)
    return File.basename(filename).gsub('.', '_').upcase() + '_';
end

# Default settings
options['OutputFile'] = 'pinning.h'
options['ConfigFile'] = File.expand_path(File.dirname(Pathname.new(__FILE__).realpath)) + '/kavrhgen.conf'

optparse = OptionParser.new do |opts|
    opts.banner = 'Usage: ' + File.basename(__FILE__) + ' [options] NETLIST'

    opts.on('-o', '--output FILE', 'Write to FILE') do |file|
        options['OutputFile'] = file
    end

    opts.on('-c', '--config FILE', 'Set configuration file') do |file|
        options['ConfigFile'] = file
    end

    opts.on('-r', '--reference REFERENCE', 'Schematic part reference of the AVR') do |ref|
        options['Reference'] = ref
    end

    opts.on('-p', '--part PART', 'Part number of the AVR') do |part|
        options['Part'] = part
    end

    opts.on('-i', '--ignore PINS', 'Ignore pins (separated by commas)') do |pins|
        options['IgnorePins'] = pins
    end

    opts.on('-h', '--help', 'Help screen') do
        puts opts
        exit
    end
end

optparse.parse!

config = YAML.load_file(options['ConfigFile'])

ARGV.each do |a|
    # Read the contents of the netlist
    ifile = File.open(a, 'r')
    netlist = ifile.read()
    ifile.close()

    # If the flags do not specify a part reference, the first one looking like
    # an AVR ist chosen from the netlist
    if options['Reference'] == nil
        refs = netlist.scan(/\(comp \(ref ([A-Z0-9]+)\)\n {6}\(value (ATTINY|ATMEGA[A-Z0-9\-_*]*)\)\n      \(footprint ([^\)]+)\)/i)
        if refs.length == 0
            puts 'Found no AVR.'
            exit 1
        elsif refs.length > 1
            puts 'Found multiple AVRs:'
            refs.each do |ref|
                puts ' ' + ref[0] + ': ' + ref[1]
            end
            puts 'Choosing ' + refs[0][0] + '. To override this, use the -r flag.'
        end
        options['Reference'] = refs[0][0]
        options['Part'] = refs[0][1]
        options['Footprint'] = refs[0][2]
    end

    # If a reference is given in the flags but no part number, the latter is
    # read from the netlist
    if options['Part'] == nil
        match = netlist.match(/\(comp \(ref #{options['Reference']}\)\n {6}\(value ([A-Z0-9\-_*]+)\)\n      \(footprint ([^\)]+)\)/)
        if match == nil
            puts 'Part "' + options['Reference'] + '" not found in netlist.'
            exit 1
        else
            options['Part'] = match[1]
            options['Footprint'] = match[2]
        end
    end

    # Check the pin assignment in the netlist and store the pin number and pin
    # name of each IO in a new hash
    iopins = Hash.new()
    pintext = netlist.match(/\(field \(name Value\) #{options['Part']}\)\n {8}\(field \(name Footprint\) #{options['Footprint']}\)\)\n {6}\(pins\n((?: {8}.*\n)+) {4}\(/)
    pins = pintext[1].scan(/num ([^\)]+)\) \(name "?([^ "]+)"?\)/)
    pins.each do |pin|
        if pin[1] =~ /P[A-Z][0-7]/
            iopins[pin[0].to_s()] = pin[1].match(/P[A-Z][0-7]/)[0]
        end
    end

    # The hash for the configuration
    pinning = Hash.new()

    # Matching the pin number directly is not possible, because multiple pins
    # can be connected to the same net. Ruby does not allow captures inside re-
    # peating groups. Thus, the pin number(s) must be extracted seperatedly.
    nets = netlist.scan(/\(net \(code .*\) \(name \/?([A-Za-z0-9,_\-+~]+)\)((?:\n {6}\(node.*)*\n {6}\(node \(ref #{options['Reference']}\) \(pin [0-9A-Z]+\)\))+/)
    ignorenets = config['IgnoreNets'].split(' ')
    ignorepins = options['IgnorePins'] == nil ? Array.new() : options['IgnorePins'].upcase.split(',');
    nets.each do |net|
        if !ignorenets.include?(net[0])
            # Matching the pin number(s)
            pins = net[1].scan(/ref #{options['Reference']}\) \(pin ([^\)]+)\)/)
            pins.delete_if do |pin|
                # Check if the pin is an IO. If it's not, dump the pin. Also
                # check if the pin should be ignored.
                if iopins[pin[0]] == nil
                    true
                elsif ignorepins.include?(pin[0])
                    true
                elsif ignorepins.include?(iopins[pin[0]])
                    true
                end
            end

            # Check if there are any pins left. If there is just one, insert
            # into the pinning hash right away. If there are more than one,
            # make a primitive enumeration
            if pins.count == 1
                pinning[net[0]] = iopins[pins[0][0]]
            elsif pins.count > 1
                pins.each_with_index do |pin, i|
                    pinning[disambiguate(net[0], i, pins[i][0])] = iopins[pins[i][0]]
                end
            end
        end
    end

    filenamedefine = escape_filename(options['OutputFile'])

    ofile = File.open(options['OutputFile'], 'w')

    ofile.puts('// This file was generated automatically by KAVRHGEN')
    ofile.puts('// Do not edit!')
    ofile.puts('')
    ofile.puts('#ifndef ' + filenamedefine)
    ofile.puts('#define ' + filenamedefine)
    ofile.puts('')
    ofile.puts('#include <avr/io.h>');
    ofile.puts('')

    pinning.sort.map do |signal, pin|
        ofile.puts(define(signal, pin, config))
        ofile.puts('')
    end

    ofile.puts('')
    ofile.puts('#endif')

    ofile.close()
end

