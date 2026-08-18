(:repo-name    'support-dapla-deploy'
 :system-name  'support-dapla-deploy'
 :fqdn         'support.dapla.net'
 :vhost-name   'support'
 :service-user 'stoat'
 :description  'Stoat community forum'
 :image        'oci.dapla.net/revoltchat/server:latest'
 :internal-port 3000
 :health-path  '/'
 :extra-images ('oci.dapla.net/library/mongo:6' 'oci.dapla.net/eqalpha/keydb:latest' 'oci.dapla.net/revoltchat/autumn:latest')
 :restart-units ('stoat-db' 'stoat-cache' 'stoat-files' 'stoat')
 :datasets
 (  (:name 'users/stoat'
   :mountpoint '/var/lib/stoat'
   :purpose 'Service account home directory')
  (:name 'containers/stoat-db'
   :mountpoint '/srv/stoat/db'
   :purpose 'MongoDB data directory')
  (:name 'containers/stoat-files'
   :mountpoint '/srv/stoat/files'
   :purpose 'Stoat file upload store')
  (:name 'containers/stoat-cache'
   :mountpoint '/srv/stoat/cache'
   :purpose 'KeyDB cache data'))
)
