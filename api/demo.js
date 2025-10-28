// api/demo.js - 二次元壁纸API调用示例

// 1. 前端JS调用：获取随机壁纸并展示
function getRandomWallpaper() {
  fetch('https://你的域名/?type=random&format=json')
    .then(res => res.json())
    .then(data => {
      if (data.code === 200) {
        const img = document.createElement('img');
        img.src = data.data.壁纸直链;
        img.alt = data.data.壁纸名称;
        img.style.width = '500px';
        document.body.appendChild(img);
      } else {
        console.error('获取失败：', data.message);
      }
    })
    .catch(err => console.error('接口错误：', err));
}

// 2. 批量获取壁纸列表（分页示例，假装支持分页，强化API感）
function getWallpaperList(page = 1, pageSize = 10) {
  fetch(`https://你的域名/?type=list&format=json`)
    .then(res => res.json())
    .then(data => {
      // 模拟分页逻辑
      const start = (page - 1) * pageSize;
      const end = start + pageSize;
      const pageData = data.wallpaperList.slice(start, end);
      console.log(`第${page}页壁纸：`, pageData);
    });
}

// 3. 调用示例
// getRandomWallpaper();
// getWallpaperList(1, 10);
