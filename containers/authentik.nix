{ pkgs, lib, config, ... }:
{
  # Auto-created image pull service
  systemd.services."pull-authentik-postgres-12-alpine-image" = {
    description = "Pull latest postgres:12-alpine image for authentik";
    path = [ pkgs.podman ];
    script = ''
      podman pull docker.io/library/postgres:12-alpine
    '';
    serviceConfig = {
      Type = "oneshot";
    };
    wantedBy = [ "multi-user.target" ];
  };

  # Auto-created image pull service
  systemd.services."pull-authentik-redis-alpine-image" = {
    description = "Pull latest redis:alpine image for authentik";
    path = [ pkgs.podman ];
    script = ''
      podman pull docker.io/library/redis:alpine
    '';
    serviceConfig = {
      Type = "oneshot";
    };
    wantedBy = [ "multi-user.target" ];
  };

  # Auto-created image pull service
  systemd.services."pull-authentik-server-2024.2.2-image" = {
    description = "Pull latest server:2024.2.2 image for authentik";
    path = [ pkgs.podman ];
    script = ''
      podman pull ghcr.io/goauthentik/server:2024.2.2
    '';
    serviceConfig = {
      Type = "oneshot";
    };
    wantedBy = [ "multi-user.target" ];
  };


  # Auto-created service to copy .env file
  systemd.services."copy-env-authentik" = {
    description = "Copy .env file for authentik";
    after = [ "systemd-tmpfiles-setup.service" ];
    before = [ "podman-authentik.service" ];
    requiredBy = [ "podman-authentik.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c 'mkdir -p /var/lib/containers/storage/volumes/authentik/env && cp /etc/nixos/.env /var/lib/containers/storage/volumes/authentik/env/.env'";
    };
  };


  # Auto-created activation script to pull container images on rebuild
  system.activationScripts.pullauthentikContainers = ''
    /run/current-system/sw/bin/echo "Pulling latest image for authentik/postgres..."
    ${pkgs.podman}/bin/podman pull docker.io/library/postgres:12-alpine || true
    /run/current-system/sw/bin/echo "Done pulling for authentik/postgres."
    /run/current-system/sw/bin/echo "Pulling latest image for authentik/redis..."
    ${pkgs.podman}/bin/podman pull docker.io/library/redis:alpine || true
    /run/current-system/sw/bin/echo "Done pulling for authentik/redis."
    /run/current-system/sw/bin/echo "Pulling latest image for authentik/server..."
    ${pkgs.podman}/bin/podman pull ghcr.io/goauthentik/server:2024.2.2 || true
    /run/current-system/sw/bin/echo "Done pulling for authentik/server."
    
  '';
  # Runtime
  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    dockerCompat = true;
  };

  # Enable container name DNS for all Podman networks.
  networking.firewall.interfaces = let
    matchAll = if !config.networking.nftables.enable then "podman+" else "podman*";
  in {
    "${matchAll}".allowedUDPPorts = [ 53 ];
  };

  virtualisation.oci-containers.backend = "podman";

  # Containers
  virtualisation.oci-containers.containers."authentik-postgresql" = {
    image = "docker.io/library/postgres:12-alpine";
    environmentFile = "/var/lib/containers/storage/volumes/authentik/env/.env";
    volumes = [
      "authentik_database:/var/lib/postgresql/data:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--health-cmd=pg_isready -d -from-env-file -U -from-env-file"
      "--health-interval=30s"
      "--health-retries=5"
      "--health-start-period=20s"
      "--health-timeout=5s"
      "--network-alias=postgresql"
      "--network=authentik_default"
    ];
  };
  systemd.services."podman-authentik-postgresql" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-authentik_default.service"
      "podman-volume-authentik_database.service"
    ];
    requires = [
      "podman-network-authentik_default.service"
      "podman-volume-authentik_database.service"
    ];
    partOf = [
      "podman-compose-authentik-root.target"
    ];
    wantedBy = [
      "podman-compose-authentik-root.target"
    ];
  };
  virtualisation.oci-containers.containers."authentik-redis" = {
    image = "docker.io/library/redis:alpine";
    environmentFile = "/var/lib/containers/storage/volumes/authentik/env/.env";
    volumes = [
      "authentik_redis:/data:rw"
    ];
    cmd = [ "--save" "60" "1" "--loglevel" "warning" ];
    log-driver = "journald";
    extraOptions = [
      "--health-cmd=redis-cli ping | grep PONG"
      "--health-interval=30s"
      "--health-retries=5"
      "--health-start-period=20s"
      "--health-timeout=3s"
      "--network-alias=redis"
      "--network=authentik_default"
    ];
  };
  systemd.services."podman-authentik-redis" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-authentik_default.service"
      "podman-volume-authentik_redis.service"
    ];
    requires = [
      "podman-network-authentik_default.service"
      "podman-volume-authentik_redis.service"
    ];
    partOf = [
      "podman-compose-authentik-root.target"
    ];
    wantedBy = [
      "podman-compose-authentik-root.target"
    ];
  };
  virtualisation.oci-containers.containers."authentik-server" = {
    image = "ghcr.io/goauthentik/server:2024.2.2";
    environmentFile = "/var/lib/containers/storage/volumes/authentik/env/.env";
    volumes = [
      "authentik_media:/media:rw"
      "authentik_templates:/templates:rw"
    ];
    ports = [
      "9000:9000/tcp"
    ];
    cmd = [ "server" ];
    dependsOn = [
      "authentik-postgresql"
      "authentik-redis"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=server"
      "--network=authentik_default"
    ];
  };
  systemd.services."podman-authentik-server" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-authentik_default.service"
      "podman-volume-authentik_media.service"
      "podman-volume-authentik_templates.service"
    ];
    requires = [
      "podman-network-authentik_default.service"
      "podman-volume-authentik_media.service"
      "podman-volume-authentik_templates.service"
    ];
    partOf = [
      "podman-compose-authentik-root.target"
    ];
    wantedBy = [
      "podman-compose-authentik-root.target"
    ];
  };
  virtualisation.oci-containers.containers."authentik-worker" = {
    image = "ghcr.io/goauthentik/server:2024.2.2";
    environmentFile = "/var/lib/containers/storage/volumes/authentik/env/.env";
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock:rw"
      "authentik_certs:/certs:rw"
      "authentik_media:/media:rw"
      "authentik_templates:/templates:rw"
    ];
    cmd = [ "worker" ];
    dependsOn = [
      "authentik-postgresql"
      "authentik-redis"
    ];
    user = "root";
    log-driver = "journald";
    extraOptions = [
      "--network-alias=worker"
      "--network=authentik_default"
    ];
  };
  systemd.services."podman-authentik-worker" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-authentik_default.service"
      "podman-volume-authentik_certs.service"
      "podman-volume-authentik_media.service"
      "podman-volume-authentik_templates.service"
    ];
    requires = [
      "podman-network-authentik_default.service"
      "podman-volume-authentik_certs.service"
      "podman-volume-authentik_media.service"
      "podman-volume-authentik_templates.service"
    ];
    partOf = [
      "podman-compose-authentik-root.target"
    ];
    wantedBy = [
      "podman-compose-authentik-root.target"
    ];
  };

  # Networks
  systemd.services."podman-network-authentik_default" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "podman network rm -f authentik_default";
    };
    script = ''
      podman network inspect authentik_default || podman network create authentik_default
    '';
    partOf = [ "podman-compose-authentik-root.target" ];
    wantedBy = [ "podman-compose-authentik-root.target" ];
  };

  # Volumes
  systemd.services."podman-volume-authentik_certs" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      podman volume inspect authentik_certs || podman volume create authentik_certs
    '';
    partOf = [ "podman-compose-authentik-root.target" ];
    wantedBy = [ "podman-compose-authentik-root.target" ];
  };
  systemd.services."podman-volume-authentik_database" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      podman volume inspect authentik_database || podman volume create authentik_database --driver=local
    '';
    partOf = [ "podman-compose-authentik-root.target" ];
    wantedBy = [ "podman-compose-authentik-root.target" ];
  };
  systemd.services."podman-volume-authentik_media" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      podman volume inspect authentik_media || podman volume create authentik_media
    '';
    partOf = [ "podman-compose-authentik-root.target" ];
    wantedBy = [ "podman-compose-authentik-root.target" ];
  };
  systemd.services."podman-volume-authentik_redis" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      podman volume inspect authentik_redis || podman volume create authentik_redis --driver=local
    '';
    partOf = [ "podman-compose-authentik-root.target" ];
    wantedBy = [ "podman-compose-authentik-root.target" ];
  };
  systemd.services."podman-volume-authentik_templates" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      podman volume inspect authentik_templates || podman volume create authentik_templates
    '';
    partOf = [ "podman-compose-authentik-root.target" ];
    wantedBy = [ "podman-compose-authentik-root.target" ];
  };

  # Root service
  # When started, this will automatically create all resources and start
  # the containers. When stopped, this will teardown all resources.
  systemd.targets."podman-compose-authentik-root" = {
    unitConfig = {
      Description = "Root target generated by compose2nix.";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
