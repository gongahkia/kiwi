#include "glyph_kdtree.hpp"

#include <cstddef>
#include <memory>
#include <stdexcept>
#include <vector>

#include "nanoflann.hpp"

namespace contourtty {
namespace {

struct GlyphFeatureDataset {
  std::size_t dims = 0;
  std::vector<double> values;

  std::size_t kdtree_get_point_count() const {
    return dims == 0 ? 0 : values.size() / dims;
  }

  double kdtree_get_pt(std::size_t index, std::size_t dim) const {
    return values[index * dims + dim];
  }

  template <class BBox>
  bool kdtree_get_bbox(BBox&) const {
    return false;
  }
};

class GlyphKdTreeIndex final : public GlyphShapeIndex {
 public:
  explicit GlyphKdTreeIndex(const GlyphShapeTable& table) {
    if (table.feature_kind != GlyphFeatureKind::Hog) {
      throw std::invalid_argument("kd-tree lookup requires HoG features");
    }
    if (table.entries.empty()) {
      throw std::invalid_argument("kd-tree lookup requires entries");
    }
    dataset_.dims = table.feature_count;
    glyphs_.reserve(table.entries.size());
    dataset_.values.reserve(table.entries.size() * table.feature_count);
    for (const GlyphShapeVector& entry : table.entries) {
      if (entry.features.size() != table.feature_count) {
        throw std::invalid_argument("glyph shape table feature length mismatch");
      }
      glyphs_.push_back(entry.glyph);
      dataset_.values.insert(dataset_.values.end(), entry.features.begin(), entry.features.end());
    }
    index_ = std::make_unique<Index>(static_cast<int>(dataset_.dims), dataset_, nanoflann::KDTreeSingleIndexAdaptorParams(1));
    index_->buildIndex();
  }

  char32_t match(std::span<const double> features) const override {
    if (features.size() != dataset_.dims) {
      throw std::invalid_argument("shape feature length mismatch");
    }
    std::size_t index = 0;
    double distance = 0.0;
    nanoflann::KNNResultSet<double, std::size_t> result_set(1);
    result_set.init(&index, &distance);
    index_->findNeighbors(result_set, features.data(), nanoflann::SearchParameters{});
    return glyphs_.at(index);
  }

 private:
  using Metric = nanoflann::L2_Simple_Adaptor<double, GlyphFeatureDataset>;
  using Index = nanoflann::KDTreeSingleIndexAdaptor<Metric, GlyphFeatureDataset, -1, std::size_t>;

  GlyphFeatureDataset dataset_;
  std::vector<char32_t> glyphs_;
  std::unique_ptr<Index> index_;
};

}  // namespace

void attachGlyphKdTree(GlyphShapeTable* table) {
  if (table == nullptr) {
    return;
  }
  table->index = std::make_shared<GlyphKdTreeIndex>(*table);
}

}  // namespace contourtty
