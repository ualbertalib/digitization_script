BagIt (for ruby)
================

[![Build Status](https://secure.travis-ci.org/no-reply/bagit.png)](http://travis-ci.org/no-reply/bagit)

Based on the [BagItspec v0.97](https://confluence.ucop.edu/display/Curation/BagIt).

Supported Features:
-------------------
* bag compiling
* manifest & tagmanifest generation
* generation of tag files bag-info.txt and bagit.txt
* fetching remote files (fetch.txt)
* bag validation

Installation
------------
    % gem install bagit validatable
The rubyforge gem is deprecated.


Example: making a bag
---------------------
    require 'bagit'

    # make a new bag at base_path
    bag = BagIt::Bag.new base_path

    # make a new file
    bag.add_file("samplefile") do |io|
      io.puts "Hello Bag!"
    end

    # generate the manifest and tagmanifest files
    bag.manifest!

Example: validating an existing bag
-----------------------------------

    bag = BagIt::Bag.new existing_base_path

    if bag.valid?
      puts "#{existing_base_path} is valid"
    else
      puts "#{existing_base_path} is not valid"
    end

Console Tool
------------
    # create a new bag/add files to existing bag
    bagit add -f file1 file2 -t tagfile1 tagfile2 ./path/to/bag	
    # validate
    bagit validate ./path/to/bag
    # for other commands
    bagit --help

TODO
----
* deep directory add/delete for bag and tag files in console tools
* better holy bag (fetch.txt) generation
* better error reporting.

---

Copyright © 2009, [Francesco Lazzarino](mailto:flazzarino@gmail.com).

Current maintainer: [Tom Johnson](mailto:thomas.johnson@oregonstate.edu).

Initial development sponsored by [Florida Center for Library Automation](http://www.fcla.edu).

See LICENSE.txt for terms.
