// Cloud Provider Definitions and Constants

export type Provider = 'aws-eks' | 'do-doks' | 'gcp-gke' | 'k3d';

export interface ProviderOption {
  value: Provider;
  label: string;
  hint: string;
}

export interface RegionOption {
  value: string;
  label: string;
}

export interface DeploymentProfile {
  value: string;
  label: string;
  hint: string;
}

export const PROVIDERS: ProviderOption[] = [
  {
    value: 'aws-eks',
    label: 'AWS EKS',
    hint: 'Production-ready managed Kubernetes on AWS',
  },
  {
    value: 'do-doks',
    label: 'DigitalOcean DOKS',
    hint: 'Simple, affordable managed Kubernetes',
  },
  {
    value: 'gcp-gke',
    label: 'GCP GKE',
    hint: 'Google Kubernetes Engine with Workload Identity',
  },
  {
    value: 'k3d',
    label: 'k3d Local',
    hint: 'Lightweight Kubernetes for local development',
  },
];

export const AWS_REGIONS: RegionOption[] = [
  { value: 'us-east-1', label: 'US East (N. Virginia)' },
  { value: 'us-east-2', label: 'US East (Ohio)' },
  { value: 'us-west-1', label: 'US West (N. California)' },
  { value: 'us-west-2', label: 'US West (Oregon)' },
  { value: 'eu-west-1', label: 'EU (Ireland)' },
  { value: 'eu-west-2', label: 'EU (London)' },
  { value: 'eu-central-1', label: 'EU (Frankfurt)' },
  { value: 'ap-southeast-1', label: 'Asia Pacific (Singapore)' },
  { value: 'ap-southeast-2', label: 'Asia Pacific (Sydney)' },
  { value: 'ap-northeast-1', label: 'Asia Pacific (Tokyo)' },
];

export const DO_REGIONS: RegionOption[] = [
  { value: 'nyc1', label: 'New York 1' },
  { value: 'nyc3', label: 'New York 3' },
  { value: 'sfo3', label: 'San Francisco 3' },
  { value: 'sgp1', label: 'Singapore 1' },
  { value: 'lon1', label: 'London 1' },
  { value: 'fra1', label: 'Frankfurt 1' },
  { value: 'tor1', label: 'Toronto 1' },
  { value: 'blr1', label: 'Bangalore 1' },
  { value: 'ams3', label: 'Amsterdam 3' },
];

export const GCP_REGIONS: RegionOption[] = [
  { value: 'us-central1', label: 'Iowa (us-central1)' },
  { value: 'us-east1', label: 'South Carolina (us-east1)' },
  { value: 'us-east4', label: 'N. Virginia (us-east4)' },
  { value: 'us-west1', label: 'Oregon (us-west1)' },
  { value: 'us-west2', label: 'Los Angeles (us-west2)' },
  { value: 'europe-west1', label: 'Belgium (europe-west1)' },
  { value: 'europe-west2', label: 'London (europe-west2)' },
  { value: 'europe-west3', label: 'Frankfurt (europe-west3)' },
  { value: 'asia-southeast1', label: 'Singapore (asia-southeast1)' },
  { value: 'asia-northeast1', label: 'Tokyo (asia-northeast1)' },
];

export const DEPLOYMENT_PROFILES: DeploymentProfile[] = [
  {
    value: 'small',
    label: 'Small (3 nodes, 1-5 clients)',
    hint: '~$200-400/month',
  },
  {
    value: 'medium',
    label: 'Medium (5 nodes, 5-15 clients)',
    hint: '~$400-800/month',
  },
  {
    value: 'large',
    label: 'Large (10+ nodes, 15+ clients)',
    hint: '~$800-1500/month',
  },
];

export interface SetupInstructions {
  title: string;
  steps: string[];
  docs?: string;
}

export const PROVIDER_SETUP_INSTRUCTIONS: Record<Provider, SetupInstructions> = {
  'aws-eks': {
    title: 'AWS Credentials Setup',
    steps: [
      '1. Create IAM user with EKS permissions',
      '2. Generate access keys in AWS Console',
      '3. Configure credentials:',
      '   export AWS_ACCESS_KEY_ID=your_key',
      '   export AWS_SECRET_ACCESS_KEY=your_secret',
      '   Or: aws configure',
    ],
    docs: 'https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html',
  },
  'do-doks': {
    title: 'DigitalOcean Token Setup',
    steps: [
      '1. Visit: https://cloud.digitalocean.com/account/api/tokens',
      '2. Generate new token with read/write scopes',
      '3. Export token:',
      '   export DIGITALOCEAN_TOKEN=your_token',
    ],
    docs: 'https://docs.digitalocean.com/reference/api/create-personal-access-token/',
  },
  'gcp-gke': {
    title: 'GCP Credentials Setup',
    steps: [
      '1. Install gcloud CLI (if not installed)',
      '2. Login and set project:',
      '   gcloud auth application-default login',
      '   gcloud config set project your-project-id',
      '3. Enable required APIs:',
      '   gcloud services enable container.googleapis.com',
      '   gcloud services enable compute.googleapis.com',
    ],
    docs: 'https://cloud.google.com/sdk/docs/authorizing',
  },
  'k3d': {
    title: 'k3d Prerequisites',
    steps: [
      '1. Ensure Docker is running',
      '2. Install k3d (if not installed):',
      '   brew install k3d (macOS)',
      '   Or: curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash',
    ],
    docs: 'https://k3d.io/v5.6.0/#installation',
  },
};
