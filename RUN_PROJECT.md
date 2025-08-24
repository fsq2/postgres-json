# دليل تشغيل المشروع الكامل

## 🚀 الخطوات الأساسية لتشغيل المشروع

### 1. **التحقق من المتطلبات الأساسية**
```bash
# التأكد من تثبيت Docker
docker --version

# التأكد من تثبيت Docker Compose
docker compose version

# التأكد من وجود مساحة كافية (أقل من 5GB)
df -h
```

### 2. **استنساخ وتشغيل المشروع**
```bash
# الانتقال إلى مجلد المشروع
cd postgres-json

# تشغيل جميع الخدمات
./setup.sh
```

### 3. **انتظار جاهزية الخدمات**
```bash
# مراقبة حالة الخدمات
docker compose ps

# انتظار حتى تصبح جميع الخدمات "healthy"
# قد يستغرق هذا 2-3 دقائق
```

### 4. **اختبار النظام**
```bash
# اختبار شامل للنظام
./test_pipeline.sh

# التأكد من أن جميع الاختبارات تمر بنجاح
```

### 5. **تشغيل معالجة البيانات**
```bash
# تشغيل Spark Streaming
./spark_stream.sh
```

## 🔍 مراقبة وتشخيص المشروع

### مراقبة شاملة
```bash
# مراقبة جميع الخدمات
./monitor.sh

# مراقبة سجلات خدمة معينة
docker compose logs -f [service-name]

# أمثلة:
docker compose logs -f postgres
docker compose logs -f debezium
docker compose logs -f redpanda
docker compose logs -f spark-master
docker compose logs -f clickhouse
docker compose logs -f redis
```

### فحص البيانات في كل مكون
```bash
# فحص PostgreSQL
docker compose exec postgres psql -U postgresuser -d pandashop -c "SELECT COUNT(*) FROM content;"
docker compose exec postgres psql -U postgresuser -d pandashop -c "SELECT COUNT(*) FROM engagement_events;"

# فحص Redpanda Topics
docker compose exec redpanda rpk topic list
docker compose exec redpanda rpk topic describe postgres.public.content

# فحص ClickHouse
docker compose exec clickhouse clickhouse-client -u app --password app -q "SELECT COUNT(*) FROM app.content_dim;"
docker compose exec clickhouse clickhouse-client -u app --password app -q "SELECT COUNT(*) FROM app.enriched_engagements;"

# فحص Redis
docker compose exec redis redis-cli ping
docker compose exec redis redis-cli xlen enriched_events
```

## 🧪 إدراج بيانات تجريبية

### إدراج محتوى جديد
```bash
docker compose exec postgres psql -U postgresuser -d pandashop -c "
INSERT INTO content (id, slug, title, content_type, length_seconds, publish_ts) VALUES
('550e8400-e29b-41d4-a716-446655440000', 'test-episode-1', 'Test Episode 1', 'podcast', 1200, NOW()),
('550e8400-e29b-41d4-a716-446655440001', 'test-video-1', 'Test Video 1', 'video', 900, NOW()),
('550e8400-e29b-41d4-a716-446655440002', 'test-newsletter-1', 'Test Newsletter 1', 'newsletter', 300, NOW())
ON CONFLICT (id) DO NOTHING;
"
```

### إدراج أحداث تفاعل
```bash
docker compose exec postgres psql -U postgresuser -d pandashop -c "
INSERT INTO engagement_events (content_id, user_id, event_type, event_ts, duration_ms, device, raw_payload) VALUES
('550e8400-e29b-41d4-a716-446655440000', '550e8400-e29b-41d4-a716-446655440010', 'play', NOW(), 30000, 'web', '{\"source\": \"test\", \"campaign\": \"demo\"}'),
('550e8400-e29b-41d4-a716-446655440000', '550e8400-e29b-41d4-a716-446655440011', 'finish', NOW(), 1200000, 'mobile', '{\"source\": \"test\", \"completed\": true}'),
('550e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440012', 'play', NOW(), 45000, 'ios', '{\"source\": \"test\"}')
ON CONFLICT (id) DO NOTHING;
"
```

## 📊 فحص تدفق البيانات

### 1. **مراقبة Redpanda Topics**
```bash
# مراقبة topic المحتوى
docker compose exec redpanda rpk topic consume postgres.public.content -n 5

# مراقبة topic أحداث التفاعل
docker compose exec redpanda rpk topic consume postgres.public.engagement_events -n 5
```

### 2. **مراقبة ClickHouse**
```bash
# فحص البيانات المُثراة
docker compose exec clickhouse clickhouse-client -u app --password app -q "
SELECT 
    event_id,
    content_title,
    event_type,
    engagement_percent,
    event_ts
FROM app.enriched_engagements 
ORDER BY event_ts DESC 
LIMIT 10;
"
```

### 3. **مراقبة Redis**
```bash
# فحص Streams
docker compose exec redis redis-cli xlen enriched_events

# قراءة آخر 5 أحداث
docker compose exec redis redis-cli xread COUNT 5 STREAMS enriched_events 0
```

## 🛠️ حل المشاكل الشائعة

### مشكلة 1: Debezium Connector لا يعمل
```bash
# فحص حالة Connector
docker compose exec debezium curl debezium:8083/connectors/postgres-connector/status

# إعادة إنشاء Connector
docker compose exec debezium curl -X DELETE debezium:8083/connectors/postgres-connector
./create_debezium_postgres_connector.sh

# فحص السجلات
docker compose logs debezium
```

### مشكلة 2: Topics لا تُنشأ في Redpanda
```bash
# فحص حالة Redpanda
docker compose exec redpanda rpk cluster health

# فحص السجلات
docker compose logs redpanda

# إعادة تشغيل Redpanda
docker compose restart redpanda
```

### مشكلة 3: Spark لا يتصل بـ ClickHouse
```bash
# فحص اتصال ClickHouse
docker compose exec clickhouse clickhouse-client -u app --password app -q "SELECT 1"

# فحص السجلات
docker compose logs clickhouse

# إعادة تشغيل ClickHouse
docker compose restart clickhouse
```

### مشكلة 4: Redis لا يستجيب
```bash
# فحص اتصال Redis
docker compose exec redis redis-cli ping

# فحص السجلات
docker compose logs redis

# إعادة تشغيل Redis
docker compose restart redis
```

### مشكلة 5: البيانات لا تتدفق
```bash
# فحص جميع الخدمات
./monitor.sh

# فحص Connector
docker compose exec debezium curl debezium:8083/connectors/postgres-connector/status

# فحص Topics
docker compose exec redpanda rpk topic list

# إدراج بيانات تجريبية
# (انظر قسم إدراج البيانات التجريبية أعلاه)
```

## 📈 اختبارات الأداء

### اختبار سرعة المعالجة
```bash
# إدراج 1000 حدث دفعة واحدة
docker compose exec postgres psql -U postgresuser -d pandashop -c "
DO \$\$
DECLARE
    i INTEGER;
    content_uuid UUID;
BEGIN
    -- الحصول على UUID محتوى موجود
    SELECT id INTO content_uuid FROM content LIMIT 1;
    
    -- إدراج 1000 حدث
    FOR i IN 1..1000 LOOP
        INSERT INTO engagement_events (content_id, user_id, event_type, event_ts, duration_ms, device, raw_payload)
        VALUES (
            content_uuid,
            gen_random_uuid(),
            CASE (i % 4)
                WHEN 0 THEN 'play'
                WHEN 1 THEN 'pause'
                WHEN 2 THEN 'finish'
                ELSE 'click'
            END,
            NOW() + (i || ' seconds')::INTERVAL,
            (random() * 300000)::INTEGER,
            CASE (i % 3)
                WHEN 0 THEN 'web'
                WHEN 1 THEN 'ios'
                ELSE 'android'
            END,
            '{\"test\": true, \"batch\": ' || i || '}'
        );
    END LOOP;
END \$\$;
"
```

### قياس الأداء
```bash
# قياس عدد الأحداث في ClickHouse
docker compose exec clickhouse clickhouse-client -u app --password app -q "
SELECT 
    count() as total_events,
    avg(engagement_percent) as avg_engagement,
    min(event_ts) as first_event,
    max(event_ts) as last_event
FROM app.enriched_engagements;
"
```

## 🔄 إعادة تشغيل النظام

### إعادة تشغيل كاملة
```bash
# إيقاف جميع الخدمات
docker compose down

# إزالة البيانات (اختياري - سيؤدي إلى فقدان البيانات)
docker compose down -v

# إعادة تشغيل
docker compose up -d

# انتظار الجاهزية
sleep 30

# إعادة إنشاء Connector
./create_debezium_postgres_connector.sh

# اختبار النظام
./test_pipeline.sh
```

### إعادة تشغيل خدمة واحدة
```bash
# إعادة تشغيل خدمة معينة
docker compose restart [service-name]

# أمثلة:
docker compose restart postgres
docker compose restart debezium
docker compose restart redpanda
docker compose restart spark-master
docker compose restart clickhouse
docker compose restart redis
```

## 📋 قائمة مراجعة التشغيل

- [ ] Docker و Docker Compose مثبتان
- [ ] جميع الخدمات تعمل (`docker compose ps`)
- [ ] Debezium Connector يعمل
- [ ] Redpanda Topics مُنشأة
- [ ] ClickHouse متصل
- [ ] Redis متصل
- [ ] البيانات تتدفق من PostgreSQL
- [ ] البيانات تظهر في Redpanda
- [ ] Spark يعالج البيانات
- [ ] البيانات تظهر في ClickHouse
- [ ] البيانات تظهر في Redis

## 🆘 الحصول على المساعدة

### عند مواجهة مشاكل
1. **فحص السجلات**: `docker compose logs [service-name]`
2. **فحص الحالة**: `./monitor.sh`
3. **اختبار الاتصال**: `./test_pipeline.sh`
4. **مراجعة التوثيق**: `README.md` و `ENHANCEMENTS.md`
5. **فتح Issue** في GitHub مع تفاصيل المشكلة

### معلومات مفيدة للمساعدة
- إصدار Docker: `docker --version`
- إصدار Docker Compose: `docker compose version`
- نظام التشغيل: `uname -a`
- سجلات الخطأ: `docker compose logs [service-name]`
- حالة الخدمات: `docker compose ps`

---

**ملاحظة**: هذا الدليل يغطي جميع الخطوات الأساسية لتشغيل المشروع. في حالة مواجهة مشاكل محددة، راجع قسم حل المشاكل الشائعة أو اطلب المساعدة. 