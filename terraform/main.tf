terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = "calcium-market-405418"
  region  = "europe-west1"
  zone    = "europe-west1-b"
}


resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ssh-enabled"]
}


resource "google_compute_firewall" "allow_web_apps" {
  name    = "allow-web-apps"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["3000", "8081"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web-enabled"]
}


resource "google_compute_instance" "cryptopulse_vm" {
  name                      = "cryptopulse-vm"
  machine_type              = "e2-medium" 
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 30 
    }
  }

  network_interface {
    network = "default"
    access_config {
     
    }
  }

  
  metadata_startup_script = <<-EOF
    #!/bin/bash
    set -e 

    
    apt-get update
    apt-get install -y ca-certificates curl gnupg lsb-release
    
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin git

   
    usermod -aG docker ubuntu

   
    if [ ! -d "/home/ubuntu/CryptoPulse" ]; then
      git clone https://github.com/MarcinPaszko/CryptoPulse.git /home/ubuntu/CryptoPulse
    fi

    cd /home/ubuntu/CryptoPulse
    
    docker compose up -d
  EOF

  tags = ["cryptopulse", "ssh-enabled", "web-enabled"]
}

output "vm_public_ip" {
  value       = google_compute_instance.cryptopulse_vm.network_interface[0].access_config[0].nat_ip
  description = "Public IP"
}
