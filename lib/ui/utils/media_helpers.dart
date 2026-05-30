import '../../core/api/api_interfaces.dart';

String mediaRouteForItem(MediaItem item) {
  switch (item.type) {
    case 'Episode':
      return '/episode/${item.id}';
    case 'Season':
      return '/season/${item.id}';
    default:
      return '/detail/${item.id}';
  }
}

List<String> resolveLibraryImageUrls(
  ApiClientFactory api,
  Library library, {
  int? maxWidth,
}) {
  return _dedupeUrls([
    if (library.primaryImageTag != null)
      api.image.getPrimaryImageUrl(
        library.id,
        tag: library.primaryImageTag,
        maxWidth: maxWidth,
      ),
  ]);
}

List<String> resolveMediaItemImageUrls(
  ApiClientFactory api,
  MediaItem item, {
  int? maxWidth,
  bool preferThumb = false,
}) {
  return _dedupeUrls([
    if (preferThumb && item.thumbImageTag != null)
      api.image.getThumbImageUrl(
        item.id,
        tag: item.thumbImageTag,
        maxWidth: maxWidth,
      ),
    if (item.primaryImageTag != null)
      api.image.getPrimaryImageUrl(
        item.id,
        tag: item.primaryImageTag,
        maxWidth: maxWidth,
      ),
    if (!preferThumb && item.thumbImageTag != null)
      api.image.getThumbImageUrl(
        item.id,
        tag: item.thumbImageTag,
        maxWidth: maxWidth,
      ),
    if (item.parentThumbItemId != null && item.parentThumbImageTag != null)
      api.image.getThumbImageUrl(
        item.parentThumbItemId!,
        tag: item.parentThumbImageTag,
        maxWidth: maxWidth,
      ),
    if (item.parentPrimaryImageItemId != null &&
        item.parentPrimaryImageTag != null)
      api.image.getPrimaryImageUrl(
        item.parentPrimaryImageItemId!,
        tag: item.parentPrimaryImageTag,
        maxWidth: maxWidth,
      ),
    if (item.seriesId != null &&
        item.seriesId!.isNotEmpty &&
        item.seriesThumbImageTag != null)
      api.image.getThumbImageUrl(
        item.seriesId!,
        tag: item.seriesThumbImageTag,
        maxWidth: maxWidth,
      ),
    if (item.seriesId != null &&
        item.seriesId!.isNotEmpty &&
        item.seriesPrimaryImageTag != null)
      api.image.getPrimaryImageUrl(
        item.seriesId!,
        tag: item.seriesPrimaryImageTag,
        maxWidth: maxWidth,
      ),
    if (item.backdropImageTag != null)
      api.image.getBackdropImageUrl(
        item.id,
        tag: item.backdropImageTag,
        maxWidth: maxWidth,
      ),
  ]);
}

List<String> resolveSeasonImageUrls(
  ApiClientFactory api,
  Season season, {
  int? maxWidth,
}) {
  // 生成多格式回退URL，确保JPG/PNG/WebP兼容性
  final urls = <String>[];
  
  // 按优先级添加各种格式的封面URL
  final formats = ['jpg', 'png', 'webp'];
  
  for (final format in formats) {
    if (season.primaryImageTag != null) {
      urls.add(api.image.getPrimaryImageUrl(
        season.id,
        tag: season.primaryImageTag,
        maxWidth: maxWidth,
        format: format,
      ));
    }
    if (season.thumbImageTag != null) {
      urls.add(api.image.getThumbImageUrl(
        season.id,
        tag: season.thumbImageTag,
        maxWidth: maxWidth,
        format: format,
      ));
    }
    if (season.seriesId.isNotEmpty && season.seriesThumbImageTag != null) {
      urls.add(api.image.getThumbImageUrl(
        season.seriesId,
        tag: season.seriesThumbImageTag,
        maxWidth: maxWidth,
        format: format,
      ));
    }
    if (season.seriesId.isNotEmpty && season.seriesPrimaryImageTag != null) {
      urls.add(api.image.getPrimaryImageUrl(
        season.seriesId,
        tag: season.seriesPrimaryImageTag,
        maxWidth: maxWidth,
        format: format,
      ));
    }
  }
  
  return _dedupeUrls(urls);
}

List<String> resolveEpisodeImageUrls(
  ApiClientFactory api,
  Episode episode, {
  int? maxWidth,
  bool preferThumb = true,
}) {
  return _dedupeUrls([
    if (preferThumb && episode.thumbImageTag != null)
      api.image.getThumbImageUrl(
        episode.id,
        tag: episode.thumbImageTag,
        maxWidth: maxWidth,
      ),
    if (episode.primaryImageTag != null)
      api.image.getPrimaryImageUrl(
        episode.id,
        tag: episode.primaryImageTag,
        maxWidth: maxWidth,
      ),
    if (!preferThumb && episode.thumbImageTag != null)
      api.image.getThumbImageUrl(
        episode.id,
        tag: episode.thumbImageTag,
        maxWidth: maxWidth,
      ),
    if (episode.parentThumbItemId != null && episode.parentThumbImageTag != null)
      api.image.getThumbImageUrl(
        episode.parentThumbItemId!,
        tag: episode.parentThumbImageTag,
        maxWidth: maxWidth,
      ),
    if (episode.parentPrimaryImageItemId != null &&
        episode.parentPrimaryImageTag != null)
      api.image.getPrimaryImageUrl(
        episode.parentPrimaryImageItemId!,
        tag: episode.parentPrimaryImageTag,
        maxWidth: maxWidth,
      ),
    if (episode.seriesId.isNotEmpty && episode.seriesThumbImageTag != null)
      api.image.getThumbImageUrl(
        episode.seriesId,
        tag: episode.seriesThumbImageTag,
        maxWidth: maxWidth,
      ),
    if (episode.seriesId.isNotEmpty && episode.seriesPrimaryImageTag != null)
      api.image.getPrimaryImageUrl(
        episode.seriesId,
        tag: episode.seriesPrimaryImageTag,
        maxWidth: maxWidth,
      ),
  ]);
}

List<String> _dedupeUrls(List<String> urls) {
  final seen = <String>{};
  final unique = <String>[];
  for (final url in urls) {
    if (url.isEmpty || !seen.add(url)) {
      continue;
    }
    unique.add(url);
  }
  return unique;
}
