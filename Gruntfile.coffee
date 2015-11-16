files =
  src:
    coffee: './src/**/*.coffee'
  test:
    coffee: './test/**/*.coffee'

module.exports = (grunt) ->
  grunt.loadNpmTasks 'grunt-coffeelint'
  grunt.loadNpmTasks 'grunt-contrib-coffee'
  grunt.loadNpmTasks 'grunt-contrib-copy'
  grunt.loadNpmTasks 'grunt-contrib-clean'
  grunt.loadNpmTasks 'grunt-contrib-watch'
  grunt.loadNpmTasks 'grunt-env'
  grunt.loadNpmTasks 'grunt-express-server'
  grunt.loadNpmTasks 'grunt-mocha-cli'

  grunt.initConfig
    clean: ['./lib/']

    env:
      dev:
        NODE_ENV: 'development'
      test:
        NODE_ENV: 'test'

    coffee:
      compile:
        options:
          bare: true
          sourceMap: true
        expand: true
        cwd: './src/'
        src: '**/*.coffee'
        dest: './lib/'
        ext: '.js'

    express:
      server:
        options:
          script: './lib/server.js'

    watch:
      src:
        files: [files.src.coffee, './config/*.json']
        tasks: ['build', 'express:server']
        options:
          spawn: false

    coffeelint:
      options:
        configFile: 'coffeelint.json'
      src:
        files:
          src: [files.src.coffee]
      test:
        files:
          src: [files.test.coffee]

    mochacli:
      options:
        reporter: 'spec'
        compilers: ['coffee:coffee-script/register']
        env:
          NODE_ENV: 'test'
          NODE_TLS_REJECT_UNAUTHORIZED: 0
        grep: grunt.option 'mochaGrep' || null
      all:
        files.test.coffee


  grunt.registerTask 'build', ['clean', 'coffee']
  grunt.registerTask 'serve', ['env:dev', 'build', 'express:server', 'watch']
  grunt.registerTask 'lint', ['coffeelint']
  grunt.registerTask 'test', ['env:test', 'coffeelint:src', 'build', 'mochacli']
