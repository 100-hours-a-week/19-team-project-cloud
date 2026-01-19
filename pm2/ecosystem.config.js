module.exports = {
    apps: [
        {
            name: 'frontend',
            script: './node_modules/next/dist/bin/next',
            args: 'start',
            cwd: '/home/ubuntu/refit/app/frontend',
            instances: 1,
            exec_mode: 'cluster',
            autorestart: true,
            max_memory_restart: '1G',
            env: {
                NODE_ENV: 'production',
                PORT: 3000,
            },
            error_file: '/home/ubuntu/refit/logs/frontend/error.log',
            out_file: '/home/ubuntu/refit/logs/frontend/out.log',
            merge_logs: true,
            log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
        },
    ],
};