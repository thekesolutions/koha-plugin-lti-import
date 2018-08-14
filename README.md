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

Once the plugin is installed, you need to tweak your _Apache_ vhost configuration for the intranet. If you are using the packages
install method (you should!) given the instance name **instance** you need to edit the
_/etc/apache2/sites-available/**instance**.conf_ file. Look for the intranet vhost and add this:

```
ScriptAlias /lti-stage.pl "/var/lib/koha/instance/plugins/Koha/Plugin/Com/ThekeSolutions/LTIImport/lti-stage.pl"
Alias /plugin "/var/lib/koha/instance/plugins"
<Directory /var/lib/koha/instance/plugins>
      Options Indexes FollowSymLinks
      AllowOverride None
      Require all granted
</Directory>
```

Then restart _apache_:
```
$ sudo systemctl restart apache2.service
```

# Configuration

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
