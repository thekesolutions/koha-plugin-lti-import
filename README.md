# koha-plugin-lti-import
A plugin for staging LTI MARC import files. It implements a configurable overlay
behaviour policy.


# Introduction

This plugin implements a MARC record staging tool, suitable to be used with LTI curated MARC
records. It allows specifying on a configuration entry what fields should be overlayed.

# Downloading

From the [release page](https://github.com/thekesolutions/koha-plugin-lti-import/releases) you can download the relevant *.kpz file

# Installing

Koha's Plugin System allows for you to add additional tools and reports to Koha that are specific to your library. Plugins are installed by uploading KPZ ( Koha Plugin Zip ) packages. A KPZ file is just a zip file containing the perl files, template files, and any other files necessary to make the plugin work.

The plugin system needs to be turned on by a system administrator.

To set up the Koha plugin system you must first make some changes to your install.

* Change `<enable_plugins>0<enable_plugins>` to `<enable_plugins>1</enable_plugins>` in your koha-conf.xml file
* Confirm that the path to `<pluginsdir>` exists, is correct, and is writable by the web server
* Restart your webserver
* Restart memcached if you are using it

Once set up is complete you will need to alter your UseKohaPlugins system preference. On the Tools page you will see the Tools Plugins and on the Reports page you will see the Reports Plugins.

# Setup

Once the plugin is installed, the steps to get your LTI import tool running we need to configure it.

The plugin configuration is a single text area that uses YAML to store the configuration options. In this example it looks like this:

```
matching_rule: 3
rules:
    - fields: 245
      filing_indicators_only: yes
    - fields: 100
    - fields: 6..
```

In this example, we are telling the plugin that the matching rule with 3 implements the biblionumber matching rule (field _999$c_).
Then, the _rules_ entry specifies a list of fields that are requested to be overlayed. The _fields_ entry should match a valid MARC
field tag. Notice _dots_ can be used as wildcards.

The _filing_indicators_only_ flag is introduced to tell the staging tool to keep _ind1_ and only overwrite _ind2_.

# Build and release

To use the new release functionality you must first install node/npm - these worked well for me:
https://nodejs.org/en/download/package-manager/#debian-and-ubuntu-based-linux-distributions

Next make sure to globally install gulp:
sudo node i gulp -g

You will need to setup a github access token:
https://help.github.com/articles/creating-an-access-token-for-command-line-use/

Then export it in into an environment variable:
export GITHUB_TOKEN={paste token here}

Before releasing update the version in package.json file

Then, use the commands:
gulp build
gulp release

The first will create the kpz, the second will create a new release on the github repoisitory and attach the kpz created above


