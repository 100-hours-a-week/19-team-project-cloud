// ⚠️ 민감한 정보는 /home/ubuntu/refit/app/ai/.env 파일에 저장하세요!
// GOOGLE_API_KEY, DATABASE_URL 등은 .env에서 자동으로 로드됩니다.

module.exports = {
    apps: [
        {
            name: 'ai-service',
            script: '/home/ubuntu/refit/app/ai/venv/bin/uvicorn',
            args: 'api.main:app --host 0.0.0.0 --port 8000',
            cwd: '/home/ubuntu/refit/app/ai/ai_app',
            interpreter: 'none', // ← 수정: uvicorn은 이미 Python 인터프리터를 포함
            instances: 1,
            exec_mode: 'fork',
            autorestart: true,
            max_memory_restart: '1G',
            
            // 기본 환경 변수 (모든 환경 공통)
            env: {
                PYTHONPATH: '/home/ubuntu/refit/app/ai/ai_app',
                PORT: '8000',
                AWS_REGION: 'ap-northeast-2',
                METRICS_ENABLED: 'true'
            },
            
            // Production 환경 (pm2 start ecosystem.ai.config.js --env production)
            env_production: {
                PYTHONPATH: '/home/ubuntu/refit/app/ai/ai_app',
                PORT: '8000',
                ENVIRONMENT: 'production',
                AWS_REGION: 'ap-northeast-2',
                METRICS_ENABLED: 'true'
            },
            
            // Development 환경 (pm2 start ecosystem.ai.config.js --env development)
            env_development: {
                PYTHONPATH: '/home/ubuntu/refit/app/ai/ai_app',
                PORT: '8000',
                ENVIRONMENT: 'development',
                AWS_REGION: 'ap-northeast-2',
                METRICS_ENABLED: 'true'
            },
            
            error_file: '/home/ubuntu/refit/logs/ai/error.log',
            out_file: '/home/ubuntu/refit/logs/ai/out.log',
            merge_logs: true,
            log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
        },
    ],
};
