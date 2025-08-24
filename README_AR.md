# نظام بث بيانات PostgreSQL مع إثراء وتحويل متعدد الوجهات

## 🎯 نظرة عامة على المشروع

هذا المشروع يقدم حلاً شاملاً لنظام بث البيانات (Data Streaming) من قاعدة بيانات PostgreSQL إلى ثلاث وجهات مختلفة مع عمليات إثراء وتحويل متقدمة. تم تصميمه لمعالجة أحداث تفاعل المستخدمين مع المحتوى في الوقت الفعلي.

## 🏗️ المعمارية التقنية

```
PostgreSQL → Debezium → Redpanda → Spark Structured Streaming → Multi-Sink Fan-out
                                                              ├── ClickHouse (تحليل البيانات)
                                                              ├── Redis (البيانات في الوقت الفعلي)
                                                              └── External System (نظام خارجي)
```

## 🧩 المكونات التقنية

### 1. **PostgreSQL** - قاعدة البيانات المصدر
- **الغرض**: تخزين كتالوج المحتوى وأحداث التفاعل
- **الجداول**: `content` و `engagement_events`
- **الميزات**: دعم JSONB، فحوصات البيانات، مراجع خارجية

### 2. **Debezium** - التقاط التغييرات (CDC)
- **الغرض**: التقاط التغييرات في PostgreSQL في الوقت الفعلي
- **الميزات**: 
  - دعم PostgreSQL 16+ مع plugin `pgoutput`
  - التقاط INSERT, UPDATE, DELETE
  - إنشاء snapshots أولية
  - معالجة الأخطاء والاسترداد

### 3. **Redpanda** - منصة البث
- **الغرض**: تخزين وإدارة تدفق البيانات
- **الميزات**:
  - توافق كامل مع Kafka
  - أداء عالي للقراءة والكتابة
  - إدارة المواضيع (Topics) تلقائياً
  - Schema Registry مدمج

### 4. **Apache Spark** - معالجة البيانات
- **الغرض**: تحويل وإثراء البيانات في الوقت الفعلي
- **الميزات**:
  - Structured Streaming للبيانات المتدفقة
  - معالجة Exactly-Once
  - دعم Checkpointing
  - معالجة متوازية

### 5. **ClickHouse** - قاعدة البيانات العمودية
- **الغرض**: تحليل البيانات والتقارير
- **الميزات**:
  - محرك MergeTree للأداء العالي
  - دعم الاستعلامات المعقدة
  - ضغط البيانات المتقدم
  - إمكانية التقسيم (Partitioning)

### 6. **Redis** - التخزين المؤقت في الوقت الفعلي
- **الغرض**: دعم الاستعلامات السريعة والتفاعلية
- **الميزات**:
  - Streams للبيانات المتسلسلة زمنياً
  - Sorted Sets للتجميعات الزمنية
  - TTL تلقائي للبيانات
  - أداء عالي (< 5 ثوانٍ)

## 📊 تصميم قاعدة البيانات

### مخطط PostgreSQL المصدر
```sql
-- كتالوج المحتوى
CREATE TABLE content (
    id              UUID PRIMARY KEY,
    slug            TEXT UNIQUE NOT NULL,
    title           TEXT        NOT NULL,
    content_type    TEXT CHECK (content_type IN ('podcast', 'newsletter', 'video')),
    length_seconds  INTEGER, 
    publish_ts      TIMESTAMPTZ NOT NULL
);

-- أحداث التفاعل الخام
CREATE TABLE engagement_events (
    id           BIGSERIAL PRIMARY KEY,
    content_id   UUID REFERENCES content(id),
    user_id      UUID,
    event_type   TEXT CHECK (event_type IN ('play', 'pause', 'finish', 'click')),
    event_ts     TIMESTAMPTZ NOT NULL,
    duration_ms  INTEGER,      -- nullable للأحداث بدون مدة
    device       TEXT,         -- مثال: "ios", "web-safari"
    raw_payload  JSONB         -- أي بيانات إضافية يرسلها العميل
);
```

### مخطط ClickHouse
```sql
-- جدول أبعاد المحتوى
CREATE TABLE app.content_dim (
  id              UUID,
  slug            String,
  title           String,
  content_type    LowCardinality(String),
  length_seconds  Int32,
  publish_ts      DateTime64(3),
  version_ts_ms   UInt64
)
ENGINE = ReplacingMergeTree(version_ts_ms)
ORDER BY id;

-- جدول حقائق التفاعل المُثرى
CREATE TABLE app.enriched_engagements (
  event_id        UInt64,
  content_id      UUID,
  user_id         UUID,
  event_type      LowCardinality(String),
  event_ts        DateTime64(3),
  duration_ms     Int32,
  device          String,
  engagement_seconds Float64,
  engagement_percent Float64,
  content_slug    String,
  content_title   String,
  content_type    LowCardinality(String),
  length_seconds  Int32,
  publish_ts      DateTime64(3),
  loaded_at       DateTime DEFAULT now()
)
ENGINE = MergeTree
ORDER BY (event_ts, content_id, event_id);
```

## 🔄 عمليات التحويل والإثراء

### 1. **ربط البيانات (Data Joins)**
- ربط `engagement_events` مع `content` للحصول على `content_type` و `length_seconds`
- استخدام LEFT JOIN لضمان عدم فقدان أحداث التفاعل

### 2. **اشتقاق الحقول الجديدة**
```python
# تحويل المدة من ميلي ثانية إلى ثانية
.withColumn("engagement_seconds", col("duration_ms") / 1000.0)

# حساب نسبة التفاعل
.withColumn("engagement_percent", 
    when((col("length_seconds").isNull()) | (col("length_seconds") == 0), lit(None))
    .otherwise(round((col("engagement_seconds") / col("length_seconds")) * 100.0, 2))
)
```

### 3. **معالجة القيم الفارغة**
- التعامل مع `NULL` في `length_seconds` و `duration_ms`
- تعيين `engagement_percent` إلى `NULL` عند عدم توفر البيانات المطلوبة

## 🎯 استراتيجية التجميع الزمني

### Redis Streams للتجميعات الزمنية
```python
# تجميع المحتويات الأكثر تفاعلاً في آخر 10 دقائق
def aggregate_recent_engagement():
    # استخدام Redis Sorted Sets مع TTL
    # تجميع حسب content_id مع مجموع engagement_percent
    # تحديث كل 10 دقائق
```

### ClickHouse للتجميعات التاريخية
```sql
-- مثال: متوسط نسبة التفاعل اليومي
SELECT 
    toDate(event_ts) as date,
    content_type,
    avg(engagement_percent) as avg_engagement
FROM app.enriched_engagements 
WHERE event_ts >= now() - INTERVAL 30 DAY
GROUP BY date, content_type
ORDER BY date DESC;
```

## 🚀 طريقة التشغيل

### 1. **إعداد البيئة**
```bash
# التأكد من تثبيت Docker و Docker Compose
docker --version
docker compose version

# استنساخ المشروع
git clone <repository-url>
cd postgres-json
```

### 2. **تشغيل النظام**
```bash
# تشغيل جميع الخدمات
./setup.sh

# اختبار النظام
./test_pipeline.sh

# تشغيل معالجة البيانات
./spark_stream.sh
```

### 3. **إدراج بيانات تجريبية**
```bash
# إدراج محتوى جديد
docker compose exec postgres psql -U postgresuser -d pandashop -c "
INSERT INTO content (id, slug, title, content_type, length_seconds, publish_ts) VALUES
('550e8400-e29b-41d4-a716-446655440000', 'test-episode', 'Test Episode', 'podcast', 1200, NOW());
"

# إدراج حدث تفاعل
docker compose exec postgres psql -U postgresuser -d pandashop -c "
INSERT INTO engagement_events (content_id, user_id, event_type, event_ts, duration_ms, device, raw_payload) VALUES
('550e8400-e29b-41d4-a716-446655440000', '550e8400-e29b-41d4-a716-446655440001', 'play', NOW(), 30000, 'web', '{\"source\": \"test\"}');
"
```

### 4. **مراقبة النظام**
```bash
# مراقبة شاملة
./monitor.sh

# مراقبة سجلات خدمة معينة
docker compose logs -f [service-name]

# فحص البيانات في ClickHouse
docker compose exec clickhouse clickhouse-client -u app --password app -q "SELECT COUNT(*) FROM app.enriched_engagements;"
```

## 📈 استراتيجية التقسيم (Partitioning)

### ClickHouse
- **التقسيم الزمني**: حسب التاريخ (`toDate(event_ts)`)
- **ترتيب البيانات**: `(event_ts, content_id, event_id)`
- **محرك الجدول**: `MergeTree` للأداء العالي

### Redis
- **Streams**: فصل حسب نوع المحتوى
- **TTL**: حذف تلقائي للبيانات القديمة
- **التجميع**: تحديث كل 10 دقائق

## 🛡️ معالجة الأخطاء والاسترداد

### 1. **Exactly-Once Processing**
- استخدام Checkpoints في Spark
- معالجة الأخطاء مع Retry Logic
- تسجيل العمليات في Redpanda

### 2. **Backfill Mechanism**
```python
# إعادة معالجة البيانات التاريخية
def backfill_historical_data(start_date, end_date):
    # قراءة البيانات من PostgreSQL
    # معالجتها عبر نفس pipeline
    # إرسالها إلى جميع الوجهات
```

### 3. **Monitoring & Alerting**
- مراقبة حالة الخدمات
- تنبيهات عند فشل المعالجة
- مقاييس الأداء والكفاءة

## 📊 مقاييس الأداء

### معايير الأداء المستهدفة
- **زمن الاستجابة Redis**: < 5 ثوانٍ
- **معالجة البيانات**: 1000+ حدث/ثانية
- **دقة المعالجة**: Exactly-Once
- **توفر النظام**: 99.9%

### مقاييس المراقبة
- عدد الأحداث المعالجة/ثانية
- زمن الاستجابة لكل وجهة
- معدل الأخطاء
- استخدام الموارد

## 🔮 التحسينات المستقبلية

### 1. **قريب المدى (1-2 أسبوع)**
- إضافة Schema Registry
- تحسين استراتيجية التقسيم
- إضافة اختبارات شاملة

### 2. **متوسط المدى (1-2 شهر)**
- إضافة Kafka Connect Sinks
- دعم أنواع محتوى جديدة
- تحسين استراتيجية التجميع

### 3. **بعيد المدى (3-6 أشهر)**
- دعم Multi-Region
- إضافة Machine Learning
- دعم Real-time Analytics

## 🧪 الاختبارات

### اختبارات الوحدة
```bash
# اختبار الاتصال
./test_pipeline.sh

# اختبار الأداء
docker compose exec spark-master /opt/bitnami/spark/bin/spark-submit --class org.apache.spark.examples.SQLPerformanceTest /opt/app/performance_test.py
```

### اختبارات التكامل
- اختبار تدفق البيانات من PostgreSQL إلى جميع الوجهات
- اختبار معالجة الأخطاء
- اختبار الأداء تحت الحمل

## 📚 المراجع والموارد

- [Apache Spark Documentation](https://spark.apache.org/docs/latest/)
- [ClickHouse Documentation](https://clickhouse.com/docs/)
- [Redis Streams](https://redis.io/docs/data-types/streams/)
- [Debezium Documentation](https://debezium.io/documentation/)

## 🤝 المساهمة والدعم

للمساهمة في المشروع:
1. Fork المشروع
2. إنشاء branch للميزة الجديدة
3. إرسال Pull Request
4. مراجعة الكود والاختبارات

للحصول على الدعم:
- فتح Issue في GitHub
- مراجعة ملفات التوثيق
- التواصل مع فريق التطوير

---

**ملاحظة**: هذا المشروع مصمم للاستخدام في بيئة التطوير والاختبار. للاستخدام في الإنتاج، يرجى مراجعة إعدادات الأمان والأداء. 