Feature: support-dapla-deploy rootless Podman quadlet deploy
  As a dapla.net operator
  I want every exported function and property verified
  So regressions are caught before reaching the host

  Background:
    Given the support-dapla-deploy/deploy system is loaded

  Scenario: Network unit uses netavark bridge
    When stoat-network-sections is called
    Then the INI contains "Driver=bridge"
    And the INI does not contain "Internal=true"

  Scenario: Network unit has correct VLSM allocation
    When stoat-network-sections is called
    Then the INI contains "Subnet=10.89.2.36/29"
    And the INI contains "Gateway=10.89.2.37"

  Scenario: stoat-db data volume uses /srv/%U/db specifier
    When stoat-db-container-sections is called
    Then a Volume line contains "/srv/%U/db"

  Scenario: stoat-cache data volume uses /srv/%U/cache specifier
    When stoat-cache-container-sections is called
    Then a Volume line contains "/srv/%U/cache"

  Scenario: stoat-files data volume uses /srv/%U/files specifier
    When stoat-files-container-sections is called
    Then a Volume line contains "/srv/%U/files"

  Scenario: stoat.container home profile is read-only via %h
    When stoat-container-sections is called
    Then a Volume line starts with "%h:"
    And that Volume line ends with ":ro"

  Scenario: stoat.container config uses /srv/%U/config specifier
    When stoat-container-sections is called
    Then a Volume line contains "/srv/%U/config"

  Scenario: stoat.container has no PublishPort
    When stoat-container-sections is called
    Then the INI does not contain "PublishPort"

  Scenario: HAProxy backend targets netavark gateway
    When haproxy-vhost-config is called
    Then the output contains "10.89.2.37"
    And the output does not contain "127.0.0.1"

  Scenario: All defprops and functions are exported and fbound
    Then haproxy-vhost-written is fbound
    And quadlets-written is fbound
    And quadlets-activated is fbound
    And zfs-encryption-key is fbound
    And zfs-dataset-mounted is fbound
    And rootless-service-account is fbound
    And images-pulled is fbound
    And decommissioned is fbound
    And deploy-app is fbound
