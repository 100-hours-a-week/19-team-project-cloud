module.exports = {
    apps: [
        {
            name: 'ai-service',
            script: '/home/ubuntu/refit/app/ai/venv/bin/uvicorn',
            args: 'api.main:app --host 0.0.0.0 --port 8000',
            cwd: '/home/ubuntu/refit/app/ai/ai_app',
            interpreter: 'none',
            instances: 1,
            exec_mode: 'fork',
            autorestart: true,
            max_memory_restart: '1G',
            env: {
                PYTHONPATH: '/home/ubuntu/refit/app/ai/ai_app',
                PORT: 8000,
                // CloudWatch 메트릭
                CLOUDWATCH_METRICS_ENABLED: 'true',
                ENVIRONMENT: 'production',
                AWS_REGION: 'ap-northeast-2',
                // AI Service API Keys
                GOOGLE_API_KEY: '***REMOVED***',
                // Database
                DATABASE_URL: 'postgresql://postgres:***REMOVED***@localhost:15432/postgres',
                // Backend API
                BACKEND_API_URL: 'https://re-fit.kr/',
            },
            env_production: {
                NODE_ENV: 'production',
                PYTHONPATH: '/home/ubuntu/refit/app/ai/ai_app',
                PORT: 8000,
                // CloudWatch 메트릭
                CLOUDWATCH_METRICS_ENABLED: 'true',
                ENVIRONMENT: 'production',
                AWS_REGION: 'ap-northeast-2',
                // AI Service API Keys
                GOOGLE_API_KEY: '***REMOVED***',
                // Database
                DATABASE_URL: 'postgresql://postgres:***REMOVED***@localhost:15432/postgres',
                // Backend API
                BACKEND_API_URL: 'https://re-fit.kr/',
            },
            error_file: '/home/ubuntu/refit/logs/ai/error.log',
            out_file: '/home/ubuntu/refit/logs/ai/out.log',
            merge_logs: true,
            log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
        },
    ],
};
